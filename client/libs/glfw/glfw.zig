const std = @import("std");
const builtin = @import("builtin");

const options = @import("options");

var glfw_allocator: ?std.mem.Allocator = null;
var pointer_size_map: std.AutoHashMapUnmanaged(usize, usize) = .empty;
var alloc_mutex: std.Thread.Mutex = .{};
const alignment: std.mem.Alignment = .of(std.c.max_align_t);

fn allocatorMissing() noreturn {
    @panic("glfw: Allocator is missing, set it through `stbi.init()`");
}

fn outOfMemory() noreturn {
    @panic("glfw: Out of memory");
}

pub const GlfwAllocatorVtable = extern struct {
    alloc: *const fn (size: usize, userdata: ?*anyopaque) callconv(.c) ?[*]u8,
    realloc: *const fn (maybe_ptr: ?*anyopaque, new_size: usize, userdata: ?*anyopaque) callconv(.c) ?[*]u8,
    free: *const fn (maybe_ptr: ?*anyopaque, userdata: ?*anyopaque) callconv(.c) void,
    userdata: ?*anyopaque,
};

fn alloc(size: usize, _: ?*anyopaque) callconv(.c) ?[*]u8 {
    const allocator = glfw_allocator orelse allocatorMissing();

    alloc_mutex.lock();
    defer alloc_mutex.unlock();

    const mem = allocator.alignedAlloc(u8, alignment, size) catch outOfMemory();
    pointer_size_map.put(allocator, @intFromPtr(mem.ptr), size) catch outOfMemory();
    return mem.ptr;
}

fn realloc(maybe_ptr: ?*anyopaque, new_size: usize, _: ?*anyopaque) callconv(.c) ?[*]u8 {
    const allocator = glfw_allocator orelse allocatorMissing();

    alloc_mutex.lock();
    defer alloc_mutex.unlock();

    const old_size = if (maybe_ptr) |p| pointer_size_map.fetchRemove(@intFromPtr(p)).?.value else 0;
    const old_mem: [*]align(alignment.toByteUnits()) u8 = if (maybe_ptr) |p| @ptrCast(@alignCast(p)) else &.{};
    const new_mem = allocator.realloc(old_mem[0..old_size], new_size) catch outOfMemory();
    pointer_size_map.put(allocator, @intFromPtr(new_mem.ptr), new_size) catch outOfMemory();
    return new_mem.ptr;
}

fn free(maybe_ptr: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    const allocator = glfw_allocator orelse allocatorMissing();
    const ptr = maybe_ptr orelse return;

    alloc_mutex.lock();
    defer alloc_mutex.unlock();

    const kv = pointer_size_map.fetchRemove(@intFromPtr(ptr)) orelse {
        std.log.err("glfw: Invalid free attempted on {*}", .{ptr});
        return;
    };
    const mem: [*]align(alignment.toByteUnits()) u8 = @ptrCast(@alignCast(ptr));
    allocator.free(mem[0..kv.value]);
}

pub fn init(allocator: std.mem.Allocator) Error!void {
    glfw_allocator = allocator;
    glfwInitAllocator(&.{
        .alloc = alloc,
        .realloc = realloc,
        .free = free,
        .userdata = null,
    });
    _ = glfwInit();
    try maybeError();
}
extern fn glfwInitAllocator(vtable: *const GlfwAllocatorVtable) void;
extern fn glfwInit() i32;

pub fn deinit() void {
    const allocator = glfw_allocator orelse allocatorMissing();
    terminate();
    pointer_size_map.deinit(allocator);
}

pub const terminate = glfwTerminate;
extern fn glfwTerminate() void;

pub const pollEvents = glfwPollEvents;
extern fn glfwPollEvents() void;

pub const waitEvents = glfwWaitEvents;
extern fn glfwWaitEvents() void;

pub const waitEventsTimeout = glfwWaitEventsTimeout;
extern fn glfwWaitEventsTimeout(timeout: f64) void;

pub fn isVulkanSupported() !bool {
    const supported = glfwVulkanSupported() == 1;
    try maybeError();
    return supported;
}
extern fn glfwVulkanSupported() i32;

pub fn getRequiredInstanceExtensions() Error![][*:0]const u8 {
    var count: u32 = 0;
    if (glfwGetRequiredInstanceExtensions(&count)) |extensions|
        return extensions[0..count];
    try maybeError();
    unreachable;
}
extern fn glfwGetRequiredInstanceExtensions(count: *u32) ?[*][*:0]const u8;

pub const getTime = glfwGetTime;
extern fn glfwGetTime() f64;

pub const setTime = glfwSetTime;
extern fn glfwSetTime(time: f64) void;

pub const Error = error{
    NotInitialized,
    NoCurrentContext,
    InvalidEnum,
    InvalidValue,
    OutOfMemory,
    ApiUnavailable,
    VersionUnavailable,
    PlatformError,
    FormatUnavailable,
    NoWindowContext,
    CursorUnavailable,
    FeatureUnavailable,
    FeatureUnimplemented,
    PlatformUnavailable,
    Unknown,
};

fn convertError(e: i32) Error!void {
    return switch (e) {
        0 => return,
        0x00010001 => Error.NotInitialized,
        0x00010002 => Error.NoCurrentContext,
        0x00010003 => Error.InvalidEnum,
        0x00010004 => Error.InvalidValue,
        0x00010005 => Error.OutOfMemory,
        0x00010006 => Error.ApiUnavailable,
        0x00010007 => Error.VersionUnavailable,
        0x00010008 => Error.PlatformError,
        0x00010009 => Error.FormatUnavailable,
        0x0001000A => Error.NoWindowContext,
        0x0001000B => Error.CursorUnavailable,
        0x0001000C => Error.FeatureUnavailable,
        0x0001000D => Error.FeatureUnimplemented,
        0x0001000E => Error.PlatformUnavailable,
        else => Error.Unknown,
    };
}

pub fn maybeError() Error!void {
    return convertError(glfwGetError(null));
}
extern fn glfwGetError(description: ?*?[*:0]const u8) i32;

pub const InputMode = enum(i32) {
    /// Not a valid enum value to pass to GLFW
    invalid = std.math.minInt(i32),

    cursor = 0x00033001,
    sticky_keys = 0x00033002,
    sticky_mouse_buttons = 0x00033003,
    lock_key_mods = 0x00033004,
    raw_mouse_motion = 0x00033005,

    fn TypeFor(self: InputMode) type {
        return switch (self) {
            .cursor => Cursor.Mode,
            .sticky_keys, .sticky_mouse_buttons, .lock_key_mods, .raw_mouse_motion => bool,
        };
    }
};

pub fn rawMouseMotionSupported() bool {
    return glfwRawMouseMotionSupported() == 1;
}
extern fn glfwRawMouseMotionSupported() i32;

pub const makeContextCurrent = glfwMakeContextCurrent;
extern fn glfwMakeContextCurrent(window: *Window) void;

pub const getCurrentContext = glfwGetCurrentContext;
extern fn glfwGetCurrentContext() *Window;

pub const swapInterval = glfwSwapInterval;
extern fn glfwSwapInterval(interval: i32) void;

pub const GlProc = *const anyopaque;
pub fn getProcAddress(procname: [*:0]const u8) ?GlProc {
    return glfwGetProcAddress(procname);
}
extern fn glfwGetProcAddress(procname: [*:0]const u8) ?GlProc;

pub const Hint = enum(i32) {
    /// Not a valid enum value to pass to GLFW
    invalid = std.math.minInt(i32),

    joystick_hat_buttons = 0x00050001,
    angle_platform_type = 0x00050002,
    platform = 0x00050003,
    cocoa_chdir_resources = 0x00051001,
    cocoa_menubar = 0x00051002,
    x11_xcb_vulkan_surface = 0x00052001,
    wayland_libdecor = 0x00053001,

    pub fn set(hint: Hint, value: i32) void {
        glfwInitHint(hint, value);
    }
    extern fn glfwInitHint(hint: Hint, value: i32) void;
};

pub const Action = enum(i32) {
    /// Not a valid enum value to pass to GLFW
    invalid = std.math.minInt(i32),

    release = 0,
    press = 1,
    repeat = 2,
};

pub const MouseButton = enum(i32) {
    /// Not a valid enum value to pass to GLFW
    invalid = std.math.minInt(i32),

    left = 0,
    right = 1,
    middle = 2,
    four = 3,
    five = 4,
    six = 5,
    seven = 6,
    eight = 7,
};

pub const Key = enum(i32) {
    /// Not a valid enum value to pass to GLFW
    invalid = std.math.minInt(i32),

    space = 32,
    apostrophe = 39,
    comma = 44,
    minus = 45,
    period = 46,
    slash = 47,
    zero = 48,
    one = 49,
    two = 50,
    three = 51,
    four = 52,
    five = 53,
    six = 54,
    seven = 55,
    eight = 56,
    nine = 57,
    semicolon = 59,
    equal = 61,
    a = 65,
    b = 66,
    c = 67,
    d = 68,
    e = 69,
    f = 70,
    g = 71,
    h = 72,
    i = 73,
    j = 74,
    k = 75,
    l = 76,
    m = 77,
    n = 78,
    o = 79,
    p = 80,
    q = 81,
    r = 82,
    s = 83,
    t = 84,
    u = 85,
    v = 86,
    w = 87,
    x = 88,
    y = 89,
    z = 90,
    left_bracket = 91,
    backslash = 92,
    right_bracket = 93,
    grave_accent = 96,
    world_1 = 161,
    world_2 = 162,

    escape = 256,
    enter = 257,
    tab = 258,
    backspace = 259,
    insert = 260,
    delete = 261,
    right = 262,
    left = 263,
    down = 264,
    up = 265,
    page_up = 266,
    page_down = 267,
    home = 268,
    end = 269,
    caps_lock = 280,
    scroll_lock = 281,
    num_lock = 282,
    print_screen = 283,
    pause = 284,
    F1 = 290,
    F2 = 291,
    F3 = 292,
    F4 = 293,
    F5 = 294,
    F6 = 295,
    F7 = 296,
    F8 = 297,
    F9 = 298,
    F10 = 299,
    F11 = 300,
    F12 = 301,
    F13 = 302,
    F14 = 303,
    F15 = 304,
    F16 = 305,
    F17 = 306,
    F18 = 307,
    F19 = 308,
    F20 = 309,
    F21 = 310,
    F22 = 311,
    F23 = 312,
    F24 = 313,
    F25 = 314,
    kp_0 = 320,
    kp_1 = 321,
    kp_2 = 322,
    kp_3 = 323,
    kp_4 = 324,
    kp_5 = 325,
    kp_6 = 326,
    kp_7 = 327,
    kp_8 = 328,
    kp_9 = 329,
    kp_decimal = 330,
    kp_divide = 331,
    kp_multiply = 332,
    kp_subtract = 333,
    kp_add = 334,
    kp_enter = 335,
    kp_equal = 336,
    left_shift = 340,
    left_control = 341,
    left_alt = 342,
    left_super = 343,
    right_shift = 344,
    right_control = 345,
    right_alt = 346,
    right_super = 347,
    menu = 348,
};

pub const Mods = packed struct(i32) {
    shift: bool = false,
    control: bool = false,
    alt: bool = false,
    super: bool = false,
    caps_lock: bool = false,
    num_lock: bool = false,
    _padding: i26 = 0,
};

pub const Image = extern struct {
    w: i32,
    h: i32,
    pixels: [*]u8,
};

pub const Cursor = opaque {
    pub const Shape = enum(i32) {
        /// Not a valid enum value to pass to GLFW
        invalid = std.math.minInt(i32),

        arrow = 0x00036001,
        ibeam = 0x00036002,
        crosshair = 0x00036003,
        hand = 0x00036004,
        resize_ew = 0x00036005,
        resize_ns = 0x00036006,
        resize_nwse = 0x00036007,
        resize_nesw = 0x00036008,
        resize_all = 0x00036009,
        not_allowed = 0x0003600A,
    };

    pub const Mode = enum(i32) {
        /// Not a valid enum value to pass to GLFW
        invalid = std.math.minInt(i32),

        normal = 0x00034001,
        hidden = 0x00034002,
        disabled = 0x00034003,
        captured = 0x00034004,
    };

    pub fn create(image: Image, x_hot: c_int, y_hot: c_int) Error!*Cursor {
        if (glfwCreateCursor(&image, x_hot, y_hot)) |ptr| return ptr;
        try maybeError();
        unreachable;
    }
    extern fn glfwCreateCursor(image: *const Image, x_hot: c_int, y_hot: c_int) ?*Cursor;

    pub const destroy = glfwDestroyCursor;
    extern fn glfwDestroyCursor(cursor: *Cursor) void;

    pub fn createStandard(shape: Shape) Error!*Cursor {
        if (glfwCreateStandardCursor(shape)) |ptr| return ptr;
        try maybeError();
        unreachable;
    }
    extern fn glfwCreateStandardCursor(shape: Shape) ?*Cursor;
};

pub const Joystick = struct {
    jid: u4,

    pub const Id = u4;
    pub const maximum_supported = std.math.maxInt(Id) + 1;

    pub const ButtonAction = enum(u8) {
        /// Not a valid enum value to pass to GLFW
        invalid = std.math.maxInt(u8),

        release = 0,
        press = 1,
    };

    pub fn getGuid(self: Joystick) [:0]const u8 {
        return std.mem.span(glfwGetJoystickGUID(@intCast(self.jid)));
    }
    extern fn glfwGetJoystickGUID(jid: i32) [*:0]const u8;

    pub fn getAxes(self: Joystick) ![]const f32 {
        var count: i32 = undefined;
        if (glfwGetJoystickAxes(@intCast(self.jid), &count)) |axes|
            return axes[0..@as(usize, @intCast(count))];
        try maybeError();
        unreachable;
    }
    extern fn glfwGetJoystickAxes(jid: i32, count: *i32) ?[*]const f32;

    pub fn getButtons(self: Joystick) ![]const ButtonAction {
        var count: i32 = undefined;
        if (glfwGetJoystickButtons(@intCast(self.jid), &count)) |buttons|
            return buttons[0..@as(usize, @intCast(count))];
        try maybeError();
        unreachable;
    }
    extern fn glfwGetJoystickButtons(jid: i32, count: *i32) ?[*]const ButtonAction;

    pub fn asGamepad(self: Joystick) ?Gamepad {
        return if (self.isGamepad()) .{ .jid = self.jid } else null;
    }
    fn isGamepad(self: Joystick) bool {
        return glfwJoystickIsGamepad(@intCast(self.jid)) == 1;
    }
    extern fn glfwJoystickIsGamepad(jid: i32) i32;

    pub fn get(jid: Id) ?Joystick {
        return if (isPresent(jid)) .{ .jid = jid } else null;
    }
    pub fn isPresent(jid: Id) bool {
        return glfwJoystickPresent(@intCast(jid)) == 1;
    }
    extern fn glfwJoystickPresent(jid: i32) i32;
};

pub const Gamepad = struct {
    jid: Joystick.Id,

    pub const Axis = enum(u8) {
        /// Not a valid enum value to pass to GLFW
        invalid = std.math.maxInt(u8),

        left_x = 0,
        left_y = 1,
        right_x = 2,
        right_y = 3,
        left_trigger = 4,
        right_trigger = 5,

        const last = Axis.right_trigger;
    };

    pub const Button = enum(u8) {
        a = 0,
        b = 1,
        x = 2,
        y = 3,
        left_bumper = 4,
        right_bumper = 5,
        back = 6,
        start = 7,
        guide = 8,
        left_thumb = 9,
        right_thumb = 10,
        dpad_up = 11,
        dpad_right = 12,
        dpad_down = 13,
        dpad_left = 14,

        const last = Button.dpad_left;

        const cross = Button.a;
        const circle = Button.b;
        const square = Button.x;
        const triangle = Button.y;
    };

    pub const State = extern struct {
        buttons: [15]Joystick.ButtonAction,
        axes: [6]f32,
    };

    pub fn getName(self: Gamepad) [:0]const u8 {
        return std.mem.span(glfwGetGamepadName(@intCast(self.jid)));
    }
    extern fn glfwGetGamepadName(jid: i32) [*:0]const u8;

    pub fn getState(self: Gamepad) State {
        var state: State = undefined;
        if (glfwGetGamepadState(@intCast(self.jid), &state) == 1)
            return state;
        try maybeError();
        unreachable;
    }
    extern fn glfwGetGamepadState(jid: i32, state: *Gamepad.State) i32;

    pub fn updateMappings(mappings: [:0]const u8) bool {
        return glfwUpdateGamepadMappings(mappings) == 1;
    }
    extern fn glfwUpdateGamepadMappings(mappings: [*:0]const u8) i32;
};

pub const Monitor = opaque {
    pub fn getPos(monitor: *Monitor) [2]i32 {
        var xpos: i32 = 0;
        var ypos: i32 = 0;
        glfwGetMonitorPos(monitor, &xpos, &ypos);
        return .{ xpos, ypos };
    }
    extern fn glfwGetMonitorPos(monitor: *Monitor, xpos: *i32, ypos: *i32) void;

    pub const getPrimary = glfwGetPrimaryMonitor;
    extern fn glfwGetPrimaryMonitor() ?*Monitor;

    pub fn getAll() ?[]*Monitor {
        var count: i32 = 0;
        if (glfwGetMonitors(&count)) |monitors|
            return monitors[0..@as(usize, @intCast(count))];
        return null;
    }
    extern fn glfwGetMonitors(count: *i32) ?[*]*Monitor;

    pub fn getName(monitor: *Monitor) Error![*:0]const u8 {
        if (glfwGetMonitorName(monitor)) |name| return name;
        try maybeError();
        unreachable;
    }
    extern fn glfwGetMonitorName(monitor: *Monitor) ?[*:0]const u8;

    pub fn getVideoMode(monitor: *Monitor) Error!*VideoMode {
        if (glfwGetVideoMode(monitor)) |video_mode| return video_mode;
        try maybeError();
        unreachable;
    }
    extern fn glfwGetVideoMode(monitor: *Monitor) ?*VideoMode;

    pub fn getVideoModes(monitor: *Monitor) Error![]VideoMode {
        var count: i32 = 0;
        if (glfwGetVideoModes(monitor, &count)) |video_modes|
            return video_modes[0..@as(usize, @intCast(count))];
        try maybeError();
        unreachable;
    }
    extern fn glfwGetVideoModes(monitor: *Monitor, count: *i32) ?[*]VideoMode;
};

pub const VideoMode = extern struct {
    width: i32,
    height: i32,
    red_bits: i32,
    green_bits: i32,
    blue_bits: i32,
    refresh_rate: i32,
};

pub const Window = opaque {
    pub const Attribute = enum(i32) {
        /// Not a valid enum value to pass to GLFW
        invalid = std.math.minInt(i32),

        focused = 0x00020001,
        iconified = 0x00020002,
        resizable = 0x00020003,
        visible = 0x00020004,
        decorated = 0x00020005,
        auto_iconify = 0x00020006,
        floating = 0x00020007,
        maximized = 0x00020008,
        center_cursor = 0x00020009,
        transparent_framebuffer = 0x0002000A,
        hovered = 0x0002000B,
        focus_on_show = 0x0002000C,
    };
    pub fn getAttribute(window: *Window, attrib: Attribute) bool {
        return glfwGetWindowAttrib(window, attrib) != 0;
    }
    extern fn glfwGetWindowAttrib(window: *Window, attrib: Attribute) i32;

    pub fn setAttribute(window: *Window, attrib: Attribute, value: bool) void {
        glfwSetWindowAttrib(window, attrib, @intFromBool(value));
    }
    extern fn glfwSetWindowAttrib(window: *Window, attrib: Attribute, value: i32) void;

    pub fn getUserPointer(window: *Window, comptime T: type) ?*T {
        return @ptrCast(@alignCast(glfwGetWindowUserPointer(window)));
    }
    extern fn glfwGetWindowUserPointer(window: *Window) ?*anyopaque;

    pub fn setUserPointer(window: *Window, pointer: ?*anyopaque) void {
        glfwSetWindowUserPointer(window, pointer);
    }
    extern fn glfwSetWindowUserPointer(window: *Window, pointer: ?*anyopaque) void;

    pub fn shouldClose(window: *Window) bool {
        return if (glfwWindowShouldClose(window) == 0) false else true;
    }
    extern fn glfwWindowShouldClose(window: *Window) i32;

    pub fn setShouldClose(window: *Window, should_close: bool) void {
        return glfwSetWindowShouldClose(window, if (should_close) 1 else 0);
    }
    extern fn glfwSetWindowShouldClose(window: *Window, should_close: i32) void;

    pub const destroy = glfwDestroyWindow;
    extern fn glfwDestroyWindow(window: *Window) void;

    pub const setSizeLimits = glfwSetWindowSizeLimits;
    extern fn glfwSetWindowSizeLimits(window: *Window, min_w: i32, min_h: i32, max_w: i32, max_h: i32) void;

    pub fn getContentScale(window: *Window) [2]f32 {
        var x_scale: f32 = 0.0;
        var y_scale: f32 = 0.0;
        glfwGetWindowContentScale(window, &x_scale, &y_scale);
        return .{ x_scale, y_scale };
    }
    extern fn glfwGetWindowContentScale(window: *Window, x_scale: *f32, y_scale: *f32) void;

    pub const getKey = glfwGetKey;
    extern fn glfwGetKey(window: *Window, key: Key) Action;

    pub const getMouseButton = glfwGetMouseButton;
    extern fn glfwGetMouseButton(window: *Window, button: MouseButton) Action;

    pub fn getCursorPos(window: *Window) [2]f64 {
        var x_pos: f64 = 0.0;
        var y_pos: f64 = 0.0;
        glfwGetCursorPos(window, &x_pos, &y_pos);
        return .{ x_pos, y_pos };
    }
    extern fn glfwGetCursorPos(window: *Window, x_pos: *f64, y_pos: *f64) void;

    pub fn getFramebufferSize(window: *Window) [2]i32 {
        var width: i32 = 0.0;
        var height: i32 = 0.0;
        glfwGetFramebufferSize(window, &width, &height);
        return .{ width, height };
    }
    extern fn glfwGetFramebufferSize(window: *Window, width: *i32, height: *i32) void;

    pub fn getSize(window: *Window) [2]i32 {
        var width: i32 = 0.0;
        var height: i32 = 0.0;
        glfwGetWindowSize(window, &width, &height);
        return .{ width, height };
    }
    extern fn glfwGetWindowSize(window: *Window, width: *i32, height: *i32) void;

    pub const setSize = glfwSetWindowSize;
    extern fn glfwSetWindowSize(window: *Window, width: i32, height: i32) void;

    pub fn getPos(window: *Window) [2]i32 {
        var x_pos: i32 = 0.0;
        var y_pos: i32 = 0.0;
        glfwGetWindowPos(window, &x_pos, &y_pos);
        return .{ x_pos, y_pos };
    }
    extern fn glfwGetWindowPos(window: *Window, x_pos: *i32, y_pos: *i32) void;

    pub const setPos = glfwSetWindowPos;
    extern fn glfwSetWindowPos(window: *Window, x_pos: i32, y_pos: i32) void;

    pub inline fn setTitle(window: *Window, title: [:0]const u8) void {
        glfwSetWindowTitle(window, title);
    }
    extern fn glfwSetWindowTitle(window: *Window, title: [*:0]const u8) void;

    pub fn getClipboardString(window: *Window) ?[:0]const u8 {
        return std.mem.span(glfwGetClipboardString(window));
    }
    extern fn glfwGetClipboardString(window: *Window) ?[*:0]const u8;

    pub inline fn setClipboardString(window: *Window, string: [:0]const u8) void {
        return glfwSetClipboardString(window, string);
    }
    extern fn glfwSetClipboardString(window: *Window, string: [*:0]const u8) void;

    pub const setFramebufferSizeCallback = glfwSetFramebufferSizeCallback;
    extern fn glfwSetFramebufferSizeCallback(window: *Window, callback: ?FramebufferSizeFn) ?FramebufferSizeFn;
    pub const FramebufferSizeFn = *const fn (
        window: *Window,
        width: i32,
        height: i32,
    ) callconv(.c) void;

    pub const setSizeCallback = glfwSetWindowSizeCallback;
    extern fn glfwSetWindowSizeCallback(window: *Window, callback: ?WindowSizeFn) ?WindowSizeFn;
    pub const WindowSizeFn = *const fn (
        window: *Window,
        width: i32,
        height: i32,
    ) callconv(.c) void;

    pub const setPosCallback = glfwSetWindowPosCallback;
    extern fn glfwSetWindowPosCallback(window: *Window, callback: ?WindowPosFn) ?WindowPosFn;
    pub const WindowPosFn = *const fn (
        window: *Window,
        xpos: i32,
        ypos: i32,
    ) callconv(.c) void;

    pub const setContentScaleCallback = glfwSetWindowContentScaleCallback;
    extern fn glfwSetWindowContentScaleCallback(window: *Window, callback: ?WindowContentScaleFn) ?WindowContentScaleFn;
    pub const WindowContentScaleFn = *const fn (
        window: *Window,
        xscale: f32,
        yscale: f32,
    ) callconv(.c) void;

    pub const setKeyCallback = glfwSetKeyCallback;
    extern fn glfwSetKeyCallback(window: *Window, callback: ?KeyFn) ?KeyFn;
    pub const KeyFn = *const fn (
        window: *Window,
        key: Key,
        scancode: i32,
        action: Action,
        mods: Mods,
    ) callconv(.c) void;

    pub const setCharCallback = glfwSetCharCallback;
    extern fn glfwSetCharCallback(window: *Window, callback: ?CharFn) ?CharFn;
    pub const CharFn = *const fn (
        window: *Window,
        codepoint: u32,
    ) callconv(.c) void;

    pub const setDropCallback = glfwSetDropCallback;
    extern fn glfwSetDropCallback(window: *Window, callback: ?DropFn) ?DropFn;
    pub const DropFn = *const fn (
        window: *Window,
        path_count: i32,
        paths: [*][*:0]const u8,
    ) callconv(.c) void;

    pub const setMouseButtonCallback = glfwSetMouseButtonCallback;
    extern fn glfwSetMouseButtonCallback(window: *Window, callback: ?MouseButtonFn) ?MouseButtonFn;
    pub const MouseButtonFn = *const fn (window: *Window, button: MouseButton, action: Action, mods: Mods) callconv(.c) void;

    pub const setCursorPosCallback = glfwSetCursorPosCallback;
    extern fn glfwSetCursorPosCallback(window: *Window, callback: ?CursorPosFn) ?CursorPosFn;
    pub const CursorPosFn = *const fn (window: *Window, xpos: f64, ypos: f64) callconv(.c) void;

    pub const setScrollCallback = glfwSetScrollCallback;
    extern fn glfwSetScrollCallback(window: *Window, callback: ?ScrollFn) ?ScrollFn;
    pub const ScrollFn = *const fn (window: *Window, xoffset: f64, yoffset: f64) callconv(.c) void;

    pub const setCursorEnterCallback = glfwSetCursorEnterCallback;
    extern fn glfwSetCursorEnterCallback(window: *Window, callback: ?CursorEnterFn) ?CursorEnterFn;
    pub const CursorEnterFn = *const fn (window: *Window, entered: i32) callconv(.c) void;

    pub const setCursor = glfwSetCursor;
    extern fn glfwSetCursor(window: *Window, cursor: ?*Cursor) void;

    pub fn setWindowIcon(window: *Window, images: []const Image) !void {
        glfwSetWindowIcon(window, @intCast(images.len), images.ptr);
        try maybeError();
    }
    extern fn glfwSetWindowIcon(window: *Window, count: i32, images: [*]const Image) void;

    pub fn setInputMode(window: *Window, comptime mode: InputMode, value: InputMode.TypeFor(mode)) void {
        glfwSetInputMode(window, mode, switch (@TypeOf(value)) {
            Cursor.Mode => @intFromEnum(mode),
            bool => @intFromBool(value),
            else => @compileError("Invalid type: `InputMode.TypeFor()` should be updated"),
        });
    }
    extern fn glfwSetInputMode(window: *Window, mode: InputMode, value: i32) void;

    pub fn focus(window: *Window) void {
        glfwFocusWindow(window);
    }
    extern fn glfwFocusWindow(window: *Window) void;

    pub const swapBuffers = glfwSwapBuffers;
    extern fn glfwSwapBuffers(window: *Window) void;

    pub fn setMonitor(window: *Window, monitor: ?*Monitor, xpos: i32, ypos: i32, width: i32, height: i32, refresh_rate: i32) void {
        glfwSetWindowMonitor(window, monitor, xpos, ypos, width, height, refresh_rate);
    }
    extern fn glfwSetWindowMonitor(window: *Window, monitor: ?*Monitor, xpos: i32, ypos: i32, width: i32, height: i32, refreshRate: i32) void;

    pub fn create(
        width: i32,
        height: i32,
        title: [:0]const u8,
        monitor: ?*Monitor,
    ) Error!*Window {
        if (glfwCreateWindow(width, height, title, monitor, null)) |window| return window;
        try maybeError();
        unreachable;
    }
    extern fn glfwCreateWindow(
        width: i32,
        height: i32,
        title: [*:0]const u8,
        monitor: ?*Monitor,
        share: ?*Window,
    ) ?*Window;

    pub fn show(window: *Window) void {
        glfwShowWindow(window);
    }
    extern fn glfwShowWindow(window: *Window) void;
};

pub const WindowHint = enum(i32) {
    /// Not a valid enum value to pass to GLFW
    invalid = std.math.minInt(i32),

    focused = 0x00020001,
    iconified = 0x00020002,
    resizable = 0x00020003,
    visible = 0x00020004,
    decorated = 0x00020005,
    auto_iconify = 0x00020006,
    floating = 0x00020007,
    maximized = 0x00020008,
    center_cursor = 0x00020009,
    transparent_framebuffer = 0x0002000A,
    hovered = 0x0002000B,
    focus_on_show = 0x0002000C,
    mouse_passthrough = 0x0002000D,
    position_x = 0x0002000E,
    position_y = 0x0002000F,
    red_bits = 0x00021001,
    green_bits = 0x00021002,
    blue_bits = 0x00021003,
    alpha_bits = 0x00021004,
    depth_bits = 0x00021005,
    stencil_bits = 0x00021006,
    stereo = 0x0002100C,
    samples = 0x0002100D,
    srgb_capable = 0x0002100E,
    refresh_rate = 0x0002100F,
    doublebuffer = 0x00021010,
    client_api = 0x00022001,
    context_version_major = 0x00022002,
    context_version_minor = 0x00022003,
    context_revision = 0x00022004,
    context_robustness = 0x00022005,
    opengl_forward_compat = 0x00022006,
    opengl_debug_context = 0x00022007,
    opengl_profile = 0x00022008,
    context_release_behaviour = 0x00022009,
    context_no_error = 0x0002200A,
    context_creation_api = 0x0002200B,
    scale_to_monitor = 0x0002200C,
    scale_framebuffer = 0x0002200D,
    cocoa_retina_framebuffer = 0x00023001,
    cocoa_frame_name = 0x00023002,
    cocoa_graphics_switching = 0x00023003,
    x11_class_name = 0x00024001,
    x11_instance_name = 0x00024002,
    win32_keyboard_menu = 0x00025001,
    win32_showdefault = 0x00025002,
    wayland_app_id = 0x00026001,

    fn TypeFor(window_hint: WindowHint) type {
        return switch (window_hint) {
            .invalid => @panic("Invalid WindowHint supplied"),
            .focused,
            .iconified,
            .resizable,
            .visible,
            .decorated,
            .auto_iconify,
            .floating,
            .maximized,
            .center_cursor,
            .transparent_framebuffer,
            .hovered,
            .focus_on_show,
            .mouse_passthrough,
            .stereo,
            .srgb_capable,
            .doublebuffer,
            .opengl_forward_compat,
            .opengl_debug_context,
            .context_no_error,
            .scale_to_monitor,
            .scale_framebuffer,
            .cocoa_retina_framebuffer,
            .cocoa_graphics_switching,
            .win32_keyboard_menu,
            .win32_showdefault,
            => bool,
            .position_x,
            .position_y,
            .red_bits,
            .green_bits,
            .blue_bits,
            .alpha_bits,
            .depth_bits,
            .stencil_bits,
            .samples,
            .refresh_rate,
            .context_version_major,
            .context_version_minor,
            .context_revision,
            => i32,
            .cocoa_frame_name,
            .x11_class_name,
            .x11_instance_name,
            .wayland_app_id,
            => [:0]const u8,
            .client_api => ClientApi,
            .context_robustness => ContextRobustness,
            .opengl_profile => OpenGLProfile,
            .context_release_behaviour => ReleaseBehaviour,
            .context_creation_api => ContextCreationApi,
        };
    }
};

pub fn windowHintTyped(
    comptime window_hint: WindowHint,
    value: WindowHint.TypeFor(window_hint),
) void {
    const HintType = WindowHint.TypeFor(window_hint);
    switch (HintType) {
        [:0]const u8 => windowHintString(window_hint, value),
        else => windowHint(window_hint, switch (@typeInfo(HintType)) {
            .int => @intCast(value),
            .@"enum" => @intFromEnum(value),
            .bool => @intFromBool(value),
            else => unreachable,
        }),
    }
}

pub const windowHint = glfwWindowHint;
extern fn glfwWindowHint(WindowHint, value: i32) void;

pub fn windowHintString(window_hint: WindowHint, string: [:0]const u8) void {
    glfwWindowHintString(window_hint, string);
}
extern fn glfwWindowHintString(WindowHint, string: [*:0]const u8) void;

pub const ClientApi = enum(i32) {
    /// Not a valid enum value to pass to GLFW
    invalid = std.math.minInt(i32),

    no_api = 0,
    opengl_api = 0x00030001,
    opengl_es_api = 0x00030002,
};

pub const OpenGLProfile = enum(i32) {
    /// Not a valid enum value to pass to GLFW
    invalid = std.math.minInt(i32),

    opengl_any_profile = 0,
    opengl_core_profile = 0x00032001,
    opengl_compat_profile = 0x00032002,
};

pub const ContextRobustness = enum(i32) {
    /// Not a valid enum value to pass to GLFW
    invalid = std.math.minInt(i32),

    no_robustness = 0,
    no_reset_notification = 0x00031001,
    lose_context_on_reset = 0x00031002,
};

pub const ReleaseBehaviour = enum(i32) {
    /// Not a valid enum value to pass to GLFW
    invalid = std.math.minInt(i32),

    any = 0,
    flush = 0x00035001,
    none = 0x00035002,
};

pub const ContextCreationApi = enum(i32) {
    /// Not a valid enum value to pass to GLFW
    invalid = std.math.minInt(i32),

    native = 0x00036001,
    egl = 0x00036002,
    osmesa = 0x00036003,
};

fn isLinuxOrBsd() bool {
    return builtin.target.os.tag == .linux or builtin.target.os.tag.isBSD();
}

fn supportsWayland() bool {
    return isLinuxOrBsd() and options.enable_wayland;
}

fn supportsX11() bool {
    return isLinuxOrBsd() and options.enable_x11;
}

pub const getWin32Adapter = if (builtin.target.os.tag == .windows)
    glfwGetWin32Adapter
else
    @compileError("This function is Windows-only");
extern fn glfwGetWin32Adapter(*Monitor) ?[*:0]const u8;

pub const getWin32Window = if (builtin.target.os.tag == .windows)
    glfwGetWin32Window
else
    @compileError("This function is Windows-only");
extern fn glfwGetWin32Window(*Window) ?std.os.windows.HWND;

pub const getCocoaWindow = if (builtin.target.os.tag == .macos)
    glfwGetCocoaWindow
else
    @compileError("This function is macOS-only");
extern fn glfwGetCocoaWindow(window: *Window) ?*anyopaque;

pub const getX11Adapter = if (supportsX11())
    glfwGetX11Adapter
else
    @compileError("X11 either is not enabled, or is unsupported by the target OS");
extern fn glfwGetX11Adapter(*Monitor) u32;

pub const getX11Display = if (supportsX11())
    glfwGetX11Display
else
    @compileError("X11 either is not enabled, or is unsupported by the target OS");
extern fn glfwGetX11Display() ?*anyopaque;

pub const getX11Window = if (supportsX11())
    glfwGetX11Window
else
    @compileError("X11 either is not enabled, or is unsupported by the target OS");
extern fn glfwGetX11Window(window: *Window) u32;

pub const getWaylandDisplay = if (supportsWayland())
    glfwGetWaylandDisplay
else
    @compileError("Wayland either is not enabled, or is unsupported by the target OS");
extern fn glfwGetWaylandDisplay() ?*anyopaque;

pub const getWaylandWindow = if (supportsWayland())
    glfwGetWaylandWindow
else
    @compileError("Wayland either is not enabled, or is unsupported by the target OS");
extern fn glfwGetWaylandWindow(window: *Window) ?*anyopaque;
