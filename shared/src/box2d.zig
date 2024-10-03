const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("box2d/base.h");
    @cInclude("box2d/box2d.h");
    @cInclude("box2d/collision.h");
    @cInclude("box2d/id.h");
    @cInclude("box2d/math_functions.h");
    @cInclude("box2d/types.h");
});

pub const castResult = fn (ShapeId, Vec2, Vec2, f32, ?*anyopaque) callconv(.C) f32;
pub const preSolve = fn (ShapeId, ShapeId, *Manifold, ?*anyopaque) callconv(.C) bool;
pub const treeQueryCallback = fn (i32, i32, ?*anyopaque) callconv(.C) bool;
pub const treeRayCastCallback = fn (*const RayCastInput, i32, i32, ?*anyopaque) callconv(.C) f32;
pub const treeShapeCastCallback = fn (*const ShapeCastInput, i32, i32, ?*anyopaque) callconv(.C) f32;
pub const overlapResult = fn (ShapeId, ?*anyopaque) callconv(.C) bool;
pub const alloc = fn (u32, i32) callconv(.C) *anyopaque;
pub const free = fn (*anyopaque) callconv(.C) void;
pub const assert = fn ([*:0]const u8, [*:0]const u8, i32) callconv(.C) i32;
pub const taskCallback = fn (i32, i32, u32, ?*anyopaque) callconv(.C) void;
pub const enqueueTaskCallback = fn (?*const taskCallback, i32, i32, ?*anyopaque, ?*anyopaque) callconv(.C) void;
pub const finishTaskCallback = fn (?*anyopaque, ?*anyopaque) callconv(.C) void;

pub const default_category_bits = c.b2_defaultCategoryBits;
pub const default_mask_bits = c.b2_defaultMaskBits;
pub const max_polygon_vertices = c.b2_maxPolygonVertices;

pub const Counters = extern struct {
    static_body_count: i32,
    body_count: i32,
    shape_count: i32,
    contact_count: i32,
    joint_count: i32,
    island_count: i32,
    stack_used: i32,
    static_tree_height: i32,
    tree_height: i32,
    byte_count: i32,
    task_count: i32,
    color_counts: [12]i32,
};

pub const MassData = extern struct { mass: f32, center: Vec2, rotational_inertia: f32 };

pub const ContactData = extern struct {
    shape_id_a: ShapeId,
    shape_id_b: ShapeId,
    manifold: Manifold,
};

pub const Segment = extern struct {
    point_1: Vec2,
    point_2: Vec2,

    pub inline fn computeAABB(shape: Segment, transform: Transform) AABB {
        return @bitCast(c.b2ComputeSegmentAABB(@ptrCast(&shape), @bitCast(transform)));
    }

    pub inline fn rayCast(self: Segment, input: RayCastInput, one_sided: bool) CastOutput {
        return @bitCast(c.b2RayCastSegment(@ptrCast(&input), @ptrCast(&self), one_sided));
    }

    pub inline fn shapeCast(self: Segment, input: ShapeCastInput) CastOutput {
        return @bitCast(c.b2ShapeCastSegment(@ptrCast(&input), @ptrCast(&self)));
    }
};

pub const ChainSegment = extern struct {
    ghost_1: Vec2,
    segment: Segment,
    ghost_2: Vec2,
    chain_id: i32,
};

pub const Profile = extern struct {
    step: f32,
    pairs: f32,
    collide: f32,
    solve: f32,
    build_islands: f32,
    solve_constraints: f32,
    prepare_tasks: f32,
    solver_tasks: f32,
    prepare_constraints: f32,
    integrate_velocities: f32,
    warm_start: f32,
    solve_velocities: f32,
    integrate_positions: f32,
    relax_velocities: f32,
    apply_restitution: f32,
    store_impulses: f32,
    finalize_bodies: f32,
    split_islands: f32,
    sleep_islands: f32,
    hit_events: f32,
    broadphase: f32,
    continuous: f32,
};

pub const Version = extern struct {
    major: i32,
    minor: i32,
    revision: i32,
};

pub const Rot = extern struct {
    cos: f32,
    sin: f32,

    pub inline fn fromRadians(angle: f32) Rot {
        return @bitCast(c.b2MakeRot(angle));
    }

    pub inline fn normalize(q: Rot) Rot {
        const mag = @sqrt((q.sin * q.sin) + (q.cos * q.cos));
        const inv_mag: f32 = if (mag > 0.0) 1.0 / mag else 0.0;
        const qn: Rot = .{ .c = q.cos * inv_mag, .s = q.sin * inv_mag };
        return qn;
    }

    pub inline fn isNormalized(q: Rot) bool {
        const qq = (q.sin * q.sin) + (q.cos * q.cos);
        return ((1.0 - 0.0006) < qq) and (qq < (1.0 + 0.0006));
    }

    pub inline fn nLerp(q1: Rot, q2: Rot, t: f32) Rot {
        const omt = 1.0 - t;
        const q: Rot = .{
            .c = (omt * q1.cos) + (t * q2.cos),
            .s = (omt * q1.sin) + (t * q2.sin),
        };
        return q.normalize();
    }

    pub inline fn integrateRotation(q1: Rot, deltaAngle: f32) Rot {
        const q2: Rot = .{
            .c = q1.cos - (deltaAngle * q1.sin),
            .s = q1.sin + (deltaAngle * q1.cos),
        };
        const mag = @sqrt((q2.sin * q2.sin) + (q2.cos * q2.cos));
        const inv_mag: f32 = if (mag > 0.0) 1.0 / mag else 0.0;
        return .{ .c = q2.cos * inv_mag, .s = q2.sin * inv_mag };
    }

    pub inline fn computeAngularVelocity(q1: Rot, q2: Rot, inv_h: f32) f32 {
        return inv_h * ((q2.sin * q1.cos) - (q2.cos * q1.sin));
    }

    pub inline fn toRadians(q: Rot) f32 {
        return atan2(q.sin, q.cos);
    }

    pub inline fn getXAxis(q: Rot) Vec2 {
        return .{ .x = q.cos, .y = q.sin };
    }

    pub inline fn getYAxis(q: Rot) Vec2 {
        return .{ .x = -q.sin, .y = q.cos };
    }

    pub inline fn mul(q: Rot, r: Rot) Rot {
        return .{
            .sin = (q.sin * r.cos) + (q.cos * r.sin),
            .cos = (q.cos * r.cos) - (q.sin * r.sin),
        };
    }

    pub inline fn invMul(q: Rot, r: Rot) Rot {
        return .{
            .sin = (q.cos * r.sin) - (q.sin * r.cos),
            .cos = (q.cos * r.cos) + (q.sin * r.sin),
        };
    }

    pub inline fn relativeAngle(b: Rot, a: Rot) f32 {
        return atan2((b.sin * a.cos) - (b.cos * a.sin), (b.cos * a.cos) + (b.sin * a.sin));
    }

    pub inline fn rotateVector(q: Rot, v: Vec2) Vec2 {
        return .{
            .x = (q.cos * v.x) - (q.sin * v.y),
            .y = (q.sin * v.x) + (q.cos * v.y),
        };
    }

    pub inline fn invRotateVector(q: Rot, v: Vec2) Vec2 {
        return .{
            .x = (q.cos * v.x) + (q.sin * v.y),
            .y = (-q.sin * v.x) + (q.cos * v.y),
        };
    }

    pub inline fn isValid(q: Rot) bool {
        return c.b2Rot_IsValid(q);
    }
};

pub const Transform = extern struct {
    p: Vec2,
    q: Rot,

    pub inline fn transformPoint(t: Transform, p: Vec2) Vec2 {
        return .{
            .x = ((t.q.cos * p.x) - (t.q.sin * p.y)) + t.p.x,
            .y = ((t.q.sin * p.x) + (t.q.cos * p.y)) + t.p.y,
        };
    }

    pub inline fn invTransformPoint(t: Transform, p: Vec2) Vec2 {
        const vx = p.x - t.p.x;
        const vy = p.y - t.p.y;
        return .{
            .x = (t.q.cos * vx) + (t.q.sin * vy),
            .y = (-t.q.sin * vx) + (t.q.cos * vy),
        };
    }

    pub inline fn mul(A: Transform, B: Transform) Transform {
        return .{
            .q = A.q.mul(B.q),
            .p = A.q.rotateVector(B.p).add(A.p),
        };
    }

    pub inline fn invMul(A: Transform, B: Transform) Transform {
        return .{
            .q = A.q.invMul(B.q),
            .p = A.q.invRotateVector(B.p.sub(A.p)),
        };
    }
};

pub const Vec2 = extern struct {
    x: f32,
    y: f32,

    pub inline fn dot(a: Vec2, b: Vec2) f32 {
        return (a.x * b.x) + (a.y * b.y);
    }

    pub inline fn cross(a: Vec2, b: Vec2) f32 {
        return (a.x * b.y) - (a.y * b.x);
    }

    pub inline fn crossVS(v: Vec2, s: f32) Vec2 {
        return .{ .x = s * v.y, .y = -s * v.x };
    }

    pub inline fn crossSV(s: f32, v: Vec2) Vec2 {
        return .{ .x = -s * v.y, .y = s * v.x };
    }

    pub inline fn leftPerp(v: Vec2) Vec2 {
        return .{ .x = -v.y, .y = v.x };
    }

    pub inline fn rightPerp(v: Vec2) Vec2 {
        return .{ .x = v.y, .y = -v.x };
    }

    pub inline fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub inline fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub inline fn neg(a: Vec2) Vec2 {
        return .{ .x = -a.x, .y = -a.y };
    }

    pub inline fn lerp(a: Vec2, b: Vec2, t: f32) Vec2 {
        return .{ .x = ((1.0 - t) * a.x) + (t * b.x), .y = ((1.0 - t) * a.y) + (t * b.y) };
    }

    pub inline fn mul(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x * b.x, .y = a.y * b.y };
    }

    pub inline fn mulSV(s: f32, v: Vec2) Vec2 {
        return .{ .x = s * v.x, .y = s * v.y };
    }

    pub inline fn mulAdd(a: Vec2, s: f32, b: Vec2) Vec2 {
        return .{ .x = a.x + (s * b.x), .y = a.y + (s * b.y) };
    }

    pub inline fn mulSub(a: Vec2, s: f32, b: Vec2) Vec2 {
        return .{ .x = a.x - (s * b.x), .y = a.y - (s * b.y) };
    }

    pub inline fn abs(a: Vec2) Vec2 {
        return .{ .x = @abs(a.x), .y = @abs(a.y) };
    }

    pub inline fn min(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = @min(a.x, b.x), .y = @min(a.y, b.y) };
    }

    pub inline fn max(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = @max(a.x, b.x), .y = @max(a.y, b.y) };
    }

    pub inline fn clamp(v: Vec2, lower: Vec2, upper: Vec2) Vec2 {
        return .{
            .x = std.math.clamp(v.x, lower.x, upper.x),
            .y = std.math.clamp(v.y, lower.y, upper.y),
        };
    }

    pub inline fn length(v: Vec2) f32 {
        return @sqrt((v.x * v.x) + (v.y * v.y));
    }

    pub inline fn lengthSquared(v: Vec2) f32 {
        return (v.x * v.x) + (v.y * v.y);
    }

    pub inline fn distance(a: Vec2, b: Vec2) f32 {
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        return @sqrt((dx * dx) + (dy * dy));
    }

    pub inline fn distanceSquared(a: Vec2, b: Vec2) f32 {
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        return (dx * dx) + (dy * dy);
    }

    pub inline fn isValid(v: Vec2) bool {
        return c.b2Vec2_IsValid(@bitCast(v));
    }

    pub inline fn normalize(v: Vec2) Vec2 {
        const len = v.length();
        if (len < std.math.floatEps(f32)) return .{ .x = 0, .y = 0 };
        const inv_len = 1.0 / len;
        return .{ .x = inv_len * v.x, .y = inv_len * v.y };
    }

    pub inline fn getLengthAndNormalize(len: *f32, v: Vec2) Vec2 {
        len.* = v.length();
        if (len.* < std.math.floatEps(f32)) return .{ .x = 0, .y = 0 };
        const inv_len = 1.0 / len.*;
        return .{ .x = inv_len * v.x, .y = inv_len * v.y };
    }
};

pub const BodyType = enum(u32) {
    static = 0,
    kinematic = 1,
    dynamic = 2,
};

pub const ShapeType = enum(u32) {
    circle = 0,
    capsule = 1,
    segment = 2,
    polygon = 3,
    chain_segment = 4,
    shape_type_count = 5,
};

pub const JointType = enum(u32) {
    distance = 0,
    motor = 1,
    mouse = 2,
    prismatic = 3,
    revolute = 4,
    weld = 5,
    wheel = 6,
};

pub const ShapeDef = extern struct {
    user_data: ?*anyopaque,
    friction: f32,
    restitution: f32,
    density: f32,
    filter: Filter,
    custom_color: u32,
    is_sensor: bool,
    enable_sensor_events: bool,
    enable_contact_events: bool,
    enable_hit_events: bool,
    enable_pre_solve_events: bool,
    force_contact_creation: bool,
    internal_value: i32,

    pub inline fn default() ShapeDef {
        return @bitCast(c.b2DefaultShapeDef());
    }
};

pub const ChainDef = extern struct {
    user_data: ?*anyopaque,
    points: [*]const Vec2,
    count: i32,
    friction: f32,
    restitution: f32,
    filter: Filter,
    is_loop: bool,
    internal_value: i32,

    pub inline fn default() ChainDef {
        return @bitCast(c.b2DefaultChainDef());
    }
};

pub const DistanceJointDef = extern struct {
    body_id_a: BodyId,
    body_id_b: BodyId,
    local_anchor_a: Vec2,
    local_anchor_b: Vec2,
    length: f32,
    enable_spring: bool,
    hertz: f32,
    damping_ratio: f32,
    enable_limit: bool,
    min_length: f32,
    max_length: f32,
    enable_motor: bool,
    max_motor_force: f32,
    motor_speed: f32,
    collide_connected: bool,
    user_data: ?*anyopaque,
    internal_value: i32,

    pub inline fn default() DistanceJointDef {
        return @bitCast(c.b2DefaultDistanceJointDef());
    }
};

pub const MotorJointDef = extern struct {
    body_id_a: BodyId,
    body_id_b: BodyId,
    linear_offset: Vec2,
    angular_offset: f32,
    max_force: f32,
    max_torque: f32,
    correction_factor: f32,
    collide_connected: bool,
    user_data: ?*anyopaque,
    internal_value: i32,

    pub inline fn default() MotorJointDef {
        return @bitCast(c.b2DefaultMotorJointDef());
    }
};

pub const MouseJointDef = extern struct {
    body_id_a: BodyId,
    body_id_b: BodyId,
    target: Vec2,
    hertz: f32,
    damping_ratio: f32,
    max_force: f32,
    collide_connected: bool,
    user_data: ?*anyopaque,
    internal_value: i32,

    pub inline fn default() MouseJointDef {
        return @bitCast(c.b2DefaultMouseJointDef());
    }
};

pub const PrismaticJointDef = extern struct {
    body_id_a: BodyId,
    body_id_b: BodyId,
    local_anchor_a: Vec2,
    local_anchor_b: Vec2,
    local_axis_a: Vec2,
    reference_angle: f32,
    enable_spring: bool,
    hertz: f32,
    damping_ratio: f32,
    enable_limit: bool,
    lower_translation: f32,
    upper_translation: f32,
    enable_motor: bool,
    max_motor_force: f32,
    motor_speed: f32,
    collide_connected: bool,
    user_data: ?*anyopaque,
    internal_value: i32,

    pub inline fn default() PrismaticJointDef {
        return @bitCast(c.b2DefaultPrismaticJointDef());
    }
};

pub const RevoluteJointDef = extern struct {
    body_id_a: BodyId,
    body_id_b: BodyId,
    local_anchor_a: Vec2,
    local_anchor_b: Vec2,
    reference_angle: f32,
    enable_spring: bool,
    hertz: f32,
    damping_ratio: f32,
    enable_limit: bool,
    lower_angle: f32,
    upper_angle: f32,
    enable_motor: bool,
    max_motor_torque: f32,
    motor_speed: f32,
    draw_size: f32,
    collide_connected: bool,
    user_data: ?*anyopaque,
    internal_value: i32,

    pub inline fn default() RevoluteJointDef {
        return @bitCast(c.b2DefaultRevoluteJointDef());
    }
};

pub const WeldJointDef = extern struct {
    body_id_a: BodyId,
    body_id_b: BodyId,
    local_anchor_a: Vec2,
    local_anchor_b: Vec2,
    reference_angle: f32,
    linear_hertz: f32,
    angular_hertz: f32,
    linear_damping_ratio: f32,
    angular_damping_ratio: f32,
    collide_connected: bool,
    user_data: ?*anyopaque,
    internal_value: i32,

    pub inline fn default() WeldJointDef {
        return @bitCast(c.b2DefaultWeldJointDef());
    }
};

pub const WheelJointDef = extern struct {
    body_id_a: BodyId,
    body_id_b: BodyId,
    local_anchor_a: Vec2,
    local_anchor_b: Vec2,
    local_axis_a: Vec2,
    enable_spring: bool,
    hertz: f32,
    damping_ratio: f32,
    enable_limit: bool,
    lower_translation: f32,
    upper_translation: f32,
    enable_motor: bool,
    max_motor_torque: f32,
    motor_speed: f32,
    collide_connected: bool,
    user_data: ?*anyopaque,
    internal_value: i32,

    pub inline fn default() WheelJointDef {
        return @bitCast(c.b2DefaultWheelJointDef());
    }
};

pub const BodyDef = extern struct {
    type: BodyType,
    position: Vec2,
    rotation: Rot,
    linear_velocity: Vec2,
    angular_velocity: f32,
    linear_damping: f32,
    angular_damping: f32,
    gravity_scale: f32,
    sleep_threshold: f32,
    user_data: ?*anyopaque,
    enable_sleep: bool,
    is_awake: bool,
    fixed_rotation: bool,
    is_bullet: bool,
    is_enabled: bool,
    automatic_mass: bool,
    allow_fast_rotation: bool,
    internal_value: i32,

    pub inline fn default() BodyDef {
        return @bitCast(c.b2DefaultBodyDef());
    }
};

pub const MixingRule = enum(u32) {
    average = 0,
    geometric_mean = 1,
    multiply = 2,
    minimum = 3,
    maximum = 4,
};

pub const WorldDef = extern struct {
    gravity: Vec2,
    restitution_threshold: f32,
    contact_pushout_velocity: f32,
    hit_event_threshold: f32,
    contact_hertz: f32,
    contact_damping_ratio: f32,
    joint_hertz: f32,
    joint_damping_ratio: f32,
    maximum_linear_velocity: f32,
    friction_mixing_rule: MixingRule,
    restitution_mixing_rule: MixingRule,
    enable_sleep: bool,
    enable_continous: bool,
    worker_count: i32,
    enqueue_callback: ?*const enqueueTaskCallback,
    finish_callback: ?*const finishTaskCallback,
    callback_context: ?*anyopaque,
    internal_value: i32,

    pub inline fn default() WorldDef {
        return @bitCast(c.b2DefaultWorldDef());
    }
};

pub const WorldId = extern struct {
    index_1: u16,
    revision: u16,

    pub inline fn create(def: WorldDef) WorldId {
        return @bitCast(c.b2CreateWorld(@ptrCast(&def)));
    }

    pub inline fn destroy(world_id: WorldId) void {
        c.b2DestroyWorld(@bitCast(world_id));
    }

    pub inline fn isValid(world_id: WorldId) bool {
        return @bitCast(c.b2World_IsValid(@bitCast(world_id)));
    }

    pub inline fn step(world_id: WorldId, time_step: f32, sub_step_count: u32) void {
        c.b2World_Step(@bitCast(world_id), time_step, @intCast(sub_step_count));
    }

    pub inline fn createDistanceJoint(world_id: WorldId, def: DistanceJointDef) JointId {
        return @bitCast(c.b2CreateDistanceJoint(@bitCast(world_id), @ptrCast(&def)));
    }

    pub inline fn createMotorJoint(world_id: WorldId, def: MotorJointDef) JointId {
        return @bitCast(c.b2CreateMotorJoint(@bitCast(world_id), @ptrCast(&def)));
    }

    pub inline fn createMouseJoint(world_id: WorldId, def: MouseJointDef) JointId {
        return @bitCast(c.b2CreateMouseJoint(@bitCast(world_id), @ptrCast(&def)));
    }

    pub inline fn createPrismaticJoint(world_id: WorldId, def: PrismaticJointDef) JointId {
        return @bitCast(c.b2CreatePrismaticJoint(@bitCast(world_id), @ptrCast(&def)));
    }

    pub inline fn createRevoluteJoint(world_id: WorldId, def: RevoluteJointDef) JointId {
        return @bitCast(c.b2CreateRevoluteJoint(@bitCast(world_id), @ptrCast(&def)));
    }

    pub inline fn createWeldJoint(world_id: WorldId, def: WeldJointDef) JointId {
        return @bitCast(c.b2CreateWeldJoint(@bitCast(world_id), @ptrCast(&def)));
    }

    pub inline fn createWheelJoint(world_id: WorldId, def: WheelJointDef) JointId {
        return @bitCast(c.b2CreateWheelJoint(@bitCast(world_id), @ptrCast(&def)));
    }

    pub inline fn getBodyEvents(world_id: WorldId) BodyEvents {
        return @bitCast(c.b2World_GetBodyEvents(@bitCast(world_id)));
    }

    pub inline fn getSensorEvents(world_id: WorldId) SensorEvents {
        return @bitCast(c.b2World_GetSensorEvents(@bitCast(world_id)));
    }

    pub inline fn getContactEvents(world_id: WorldId) ContactEvents {
        return @bitCast(c.b2World_GetContactEvents(@bitCast(world_id)));
    }

    pub inline fn overlapAABB(world_id: WorldId, aabb: AABB, filter: QueryFilter, callback: ?*const overlapResult, context: ?*anyopaque) void {
        c.b2World_OverlapAABB(@bitCast(world_id), @bitCast(aabb), @bitCast(filter), @ptrCast(callback), @ptrCast(context));
    }

    pub inline fn overlapCircle(world_id: WorldId, circle: Circle, transform: Transform, filter: QueryFilter, callback: ?*const overlapResult, context: ?*anyopaque) void {
        c.b2World_OverlapCircle(@bitCast(world_id), @ptrCast(&circle), @bitCast(transform), @bitCast(filter), @ptrCast(callback), @ptrCast(context));
    }

    pub inline fn overlapCapsule(world_id: WorldId, capsule: Capsule, transform: Transform, filter: QueryFilter, callback: ?*const overlapResult, context: ?*anyopaque) void {
        c.b2World_OverlapCapsule(@bitCast(world_id), @ptrCast(&capsule), @bitCast(transform), @bitCast(filter), @ptrCast(callback), @ptrCast(context));
    }

    pub inline fn overlapPolygon(world_id: WorldId, polygon: Polygon, transform: Transform, filter: QueryFilter, callback: ?*const overlapResult, context: ?*anyopaque) void {
        c.b2World_OverlapPolygon(@bitCast(world_id), @ptrCast(&polygon), @bitCast(transform), @bitCast(filter), @ptrCast(callback), @ptrCast(context));
    }

    pub inline fn castRay(world_id: WorldId, origin: Vec2, translation: Vec2, filter: QueryFilter, callback: ?*const castResult, context: ?*anyopaque) void {
        c.b2World_CastRay(@bitCast(world_id), @bitCast(origin), @bitCast(translation), @bitCast(filter), @ptrCast(callback), @ptrCast(context));
    }

    pub inline fn rayCastClosest(world_id: WorldId, origin: Vec2, translation: Vec2, filter: QueryFilter) RayResult {
        return @bitCast(c.b2World_RayCastClosest(@bitCast(world_id), @bitCast(origin), @bitCast(translation), @bitCast(filter)));
    }

    pub inline fn castCircle(world_id: WorldId, circle: Circle, origin_transform: Transform, translation: Vec2, filter: QueryFilter, callback: ?*const castResult, context: ?*anyopaque) void {
        c.b2World_CastCircle(@bitCast(world_id), @ptrCast(&circle), @bitCast(origin_transform), @bitCast(translation), @bitCast(filter), @ptrCast(callback), @ptrCast(context));
    }

    pub inline fn castCapsule(world_id: WorldId, capsule: Capsule, origin_transform: Transform, translation: Vec2, filter: QueryFilter, callback: ?*const castResult, context: ?*anyopaque) void {
        c.b2World_CastCapsule(@bitCast(world_id), @ptrCast(&capsule), @bitCast(origin_transform), @bitCast(translation), @bitCast(filter), @ptrCast(callback), @ptrCast(context));
    }

    pub inline fn castPolygon(world_id: WorldId, polygon: Polygon, origin_transform: Transform, translation: Vec2, filter: QueryFilter, callback: ?*const castResult, context: ?*anyopaque) void {
        c.b2World_CastPolygon(@bitCast(world_id), @ptrCast(&polygon), @bitCast(origin_transform), @bitCast(translation), @bitCast(filter), @ptrCast(callback), @ptrCast(context));
    }

    pub inline fn enableSleeping(world_id: WorldId, flag: bool) void {
        c.b2World_EnableSleeping(@bitCast(world_id), flag);
    }

    pub inline fn enableWarmStarting(world_id: WorldId, flag: bool) void {
        c.b2World_EnableWarmStarting(@bitCast(world_id), flag);
    }

    pub inline fn enableContinuous(world_id: WorldId, flag: bool) void {
        c.b2World_EnableContinuous(@bitCast(world_id), flag);
    }

    pub inline fn setRestitutionThreshold(world_id: WorldId, value: f32) void {
        c.b2World_SetRestitutionThreshold(@bitCast(world_id), value);
    }

    pub inline fn setHitEventThreshold(world_id: WorldId, value: f32) void {
        c.b2World_SetHitEventThreshold(@bitCast(world_id), value);
    }

    pub inline fn setPreSolveCallback(world_id: WorldId, callback: ?*const preSolve, context: ?*anyopaque) void {
        c.b2World_SetPreSolveCallback(@bitCast(world_id), @ptrCast(callback), @ptrCast(context));
    }

    pub inline fn setGravity(world_id: WorldId, gravity: Vec2) void {
        c.b2World_SetGravity(@bitCast(world_id), @bitCast(gravity));
    }

    pub inline fn getGravity(world_id: WorldId) Vec2 {
        return @bitCast(c.b2World_GetGravity(@bitCast(world_id)));
    }

    pub inline fn explode(world_id: WorldId, position: Vec2, radius: f32, impulse: f32) void {
        c.b2World_Explode(@bitCast(world_id), @bitCast(position), radius, impulse);
    }

    pub inline fn setContactTuning(world_id: WorldId, hertz: f32, damping_ratio: f32, push_velocity: f32) void {
        c.b2World_SetContactTuning(@bitCast(world_id), hertz, damping_ratio, push_velocity);
    }

    pub inline fn getProfile(world_id: WorldId) Profile {
        return @bitCast(c.b2World_GetProfile(@bitCast(world_id)));
    }

    pub inline fn getCounters(world_id: WorldId) Counters {
        return @bitCast(c.b2World_GetCounters(@bitCast(world_id)));
    }

    pub inline fn dumpMemoryStats(world_id: WorldId) void {
        c.b2World_DumpMemoryStats(@bitCast(world_id));
    }
};

pub const JointId = extern struct {
    index_1: i32,
    world_0: u16,
    revision: u16,

    pub inline fn destroy(joint_id: JointId) void {
        return c.b2DestroyJoint(@bitCast(joint_id));
    }

    pub inline fn isValid(joint_id: JointId) bool {
        return c.b2Joint_IsValid(@bitCast(joint_id));
    }

    pub inline fn getType(joint_id: JointId) JointType {
        return @bitCast(c.b2Joint_GetType(@bitCast(joint_id)));
    }

    pub inline fn getBodyA(joint_id: JointId) BodyId {
        return @bitCast(c.b2Joint_GetBodyA(@bitCast(joint_id)));
    }

    pub inline fn getBodyB(joint_id: JointId) BodyId {
        return @bitCast(c.b2Joint_GetBodyB(@bitCast(joint_id)));
    }

    pub inline fn getLocalAnchorA(joint_id: JointId) Vec2 {
        return @bitCast(c.b2Joint_GetLocalAnchorA(@bitCast(joint_id)));
    }

    pub inline fn getLocalAnchorB(joint_id: JointId) Vec2 {
        return @bitCast(c.b2Joint_GetLocalAnchorB(@bitCast(joint_id)));
    }

    pub inline fn setCollideConnected(joint_id: JointId, enable: bool) void {
        c.b2Joint_SetCollideConnected(@bitCast(joint_id), enable);
    }

    pub inline fn getCollideConnected(joint_id: JointId) bool {
        return c.b2Joint_GetCollideConnected(@bitCast(joint_id));
    }

    pub inline fn setUserData(joint_id: JointId, user_data: ?*anyopaque) void {
        c.b2Joint_SetUserData(@bitCast(joint_id), @ptrCast(user_data));
    }

    pub inline fn getUserData(joint_id: JointId) ?*anyopaque {
        return @ptrCast(c.b2Joint_GetUserData(@bitCast(joint_id)));
    }

    pub inline fn wakeBodies(joint_id: JointId) void {
        c.b2Joint_WakeBodies(@bitCast(joint_id));
    }

    pub inline fn getConstraintForce(joint_id: JointId) void {
        c.b2Joint_GetConstraintForce(@bitCast(joint_id));
    }

    pub inline fn getConstraintTorque(joint_id: JointId) void {
        c.b2Joint_GetConstraintTorque(@bitCast(joint_id));
    }

    pub inline fn distanceJointSetLength(joint_id: JointId, length: f32) void {
        return c.b2DistanceJoint_SetLength(@bitCast(joint_id), length);
    }

    pub inline fn distanceJointGetLength(joint_id: JointId) f32 {
        return distanceJointGetLength(@bitCast(joint_id));
    }

    pub inline fn distanceJointEnableSpring(joint_id: JointId, enable: bool) void {
        c.b2DistanceJoint_EnableSpring(@bitCast(joint_id), enable);
    }

    pub inline fn distanceJointIsSpringEnabled(joint_id: JointId) bool {
        return c.b2DistanceJoint_IsSpringEnabled(@bitCast(joint_id));
    }

    pub inline fn distanceJointSetSpringHertz(joint_id: JointId, hertz: f32) void {
        c.b2DistanceJoint_SetSpringHertz(@bitCast(joint_id), hertz);
    }

    pub inline fn distanceJointSetSpringDampingRatio(joint_id: JointId, ratio: f32) void {
        c.b2DistanceJoint_SetSpringDampingRatio(@bitCast(joint_id), ratio);
    }

    pub inline fn distanceJointGetSpringHertz(joint_id: JointId) f32 {
        return c.b2DistanceJoint_GetSpringHertz(@bitCast(joint_id));
    }

    pub inline fn distanceJointGetSpringDampingRatio(joint_id: JointId) f32 {
        return c.b2DistanceJoint_GetSpringDampingRatio(@bitCast(joint_id));
    }

    pub inline fn distanceJointEnableLimit(joint_id: JointId, enable: bool) void {
        return c.b2DistanceJoint_EnableLimit(@bitCast(joint_id), enable);
    }

    pub inline fn distanceJointIsLimitEnabled(joint_id: JointId) bool {
        return c.b2DistanceJoint_IsLimitEnabled(@bitCast(joint_id));
    }

    pub inline fn distanceJointSetLengthRange(joint_id: JointId, min: f32, max: f32) void {
        c.b2DistanceJoint_SetLengthRange(@bitCast(joint_id), min, max);
    }

    pub inline fn distanceJointGetMinLength(joint_id: JointId) f32 {
        return c.b2DistanceJoint_GetMinLength(@bitCast(joint_id));
    }

    pub inline fn distanceJointGetMaxLength(joint_id: JointId) f32 {
        return c.b2DistanceJoint_GetMaxLength(@bitCast(joint_id));
    }

    pub inline fn distanceJointGetCurrentLength(joint_id: JointId) f32 {
        return c.b2DistanceJoint_GetCurrentLength(@bitCast(joint_id));
    }

    pub inline fn distanceJointEnableMotor(joint_id: JointId, enable: bool) void {
        c.b2DistanceJoint_EnableMotor(@bitCast(joint_id), enable);
    }

    pub inline fn distanceJointIsMotorEnabled(joint_id: JointId) bool {
        return c.b2DistanceJoint_IsMotorEnabled(@bitCast(joint_id));
    }

    pub inline fn distanceJointSetMotorSpeed(joint_id: JointId, speed: f32) void {
        c.b2DistanceJoint_SetMotorSpeed(@bitCast(joint_id), speed);
    }

    pub inline fn distanceJointGetMotorSpeed(joint_id: JointId) f32 {
        return c.b2DistanceJoint_GetMotorSpeed(@bitCast(joint_id));
    }

    pub inline fn distanceJointGetMotorForce(joint_id: JointId) f32 {
        return c.b2DistanceJoint_GetMotorForce(@bitCast(joint_id));
    }

    pub inline fn distanceJointSetMaxMotorForce(joint_id: JointId, force: f32) void {
        c.b2DistanceJoint_SetMaxMotorForce(@bitCast(joint_id), force);
    }

    pub inline fn distanceJointGetMaxMotorForce(joint_id: JointId) f32 {
        return c.b2DistanceJoint_GetMaxMotorForce(@bitCast(joint_id));
    }

    pub inline fn motorJointSetLinearOffset(joint_id: JointId, offset: Vec2) void {
        c.b2MotorJoint_SetLinearOffset(@bitCast(joint_id), offset);
    }

    pub inline fn motorJointGetLinearOffset(joint_id: JointId) Vec2 {
        return @bitCast(c.b2MotorJoint_GetLinearOffset(@bitCast(joint_id)));
    }

    pub inline fn motorJointSetAngularOffset(joint_id: JointId, offset: f32) void {
        c.b2MotorJoint_SetAngularOffset(@bitCast(joint_id), offset);
    }

    pub inline fn motorJointGetAngularOffset(joint_id: JointId) f32 {
        return c.b2MotorJoint_GetAngularOffset(@bitCast(joint_id));
    }

    pub inline fn motorJointSetMaxForce(joint_id: JointId, force: f32) void {
        c.b2MotorJoint_SetMaxForce(@bitCast(joint_id), force);
    }

    pub inline fn motorJointGetMaxForce(joint_id: JointId) f32 {
        return c.b2MotorJoint_GetMaxForce(@bitCast(joint_id));
    }

    pub inline fn motorJointSetMaxTorque(joint_id: JointId, torque: f32) void {
        c.b2MotorJoint_SetMaxTorque(@bitCast(joint_id), torque);
    }

    pub inline fn motorJointGetMaxTorque(joint_id: JointId) f32 {
        return c.b2MotorJoint_GetMaxTorque(@bitCast(joint_id));
    }

    pub inline fn motorJointSetCorrectionFactor(joint_id: JointId, factor: f32) void {
        c.b2MotorJoint_SetCorrectionFactor(@bitCast(joint_id), factor);
    }

    pub inline fn motorJointGetCorrectionFactor(joint_id: JointId) f32 {
        return c.b2MotorJoint_GetCorrectionFactor(@bitCast(joint_id));
    }

    pub inline fn mouseJointSetTarget(joint_id: JointId, target: Vec2) void {
        c.b2MouseJoint_SetTarget(@bitCast(joint_id), @bitCast(target));
    }

    pub inline fn mouseJointGetTarget(joint_id: JointId) Vec2 {
        return @bitCast(c.b2MouseJoint_GetTarget(@bitCast(joint_id)));
    }

    pub inline fn mouseJointSetSpringHertz(joint_id: JointId, hertz: f32) void {
        c.b2MouseJoint_SetSpringHertz(@bitCast(joint_id), hertz);
    }

    pub inline fn mouseJointGetSpringHertz(joint_id: JointId) f32 {
        return c.b2MouseJoint_GetSpringHertz(@bitCast(joint_id));
    }

    pub inline fn mouseJointSetMaxForce(joint_id: JointId, force: f32) void {
        c.b2MouseJoint_SetMaxForce(@bitCast(joint_id), force);
    }

    pub inline fn mouseJointGetMaxForce(joint_id: JointId) f32 {
        return c.b2MouseJoint_GetMaxForce(@bitCast(joint_id));
    }

    pub inline fn mouseJointSetSpringDampingRatio(joint_id: JointId, ratio: f32) void {
        c.b2MouseJoint_SetSpringDampingRatio(@bitCast(joint_id), ratio);
    }

    pub inline fn mouseJointGetSpringDampingRatio(joint_id: JointId) f32 {
        return c.b2MouseJoint_GetSpringDampingRatio(@bitCast(joint_id));
    }

    pub inline fn prismaticJointEnableSpring(joint_id: JointId, enable: bool) void {
        c.b2PrismaticJoint_EnableSpring(@bitCast(joint_id), enable);
    }

    pub inline fn prismaticJointIsSpringEnabled(joint_id: JointId) bool {
        return c.b2PrismaticJoint_IsSpringEnabled(@bitCast(joint_id));
    }

    pub inline fn prismaticJointSetSpringHertz(joint_id: JointId, hertz: f32) void {
        c.b2PrismaticJoint_SetSpringHertz(@bitCast(joint_id), hertz);
    }

    pub inline fn prismaticJointGetSpringHertz(joint_id: JointId) f32 {
        return c.b2PrismaticJoint_GetSpringHertz(@bitCast(joint_id));
    }

    pub inline fn prismaticJointSetSpringDampingRatio(joint_id: JointId, ratio: f32) void {
        c.b2PrismaticJoint_SetSpringDampingRatio(@bitCast(joint_id), ratio);
    }

    pub inline fn prismaticJointGetSpringDampingRatio(joint_id: JointId) f32 {
        return c.b2PrismaticJoint_GetSpringDampingRatio(@bitCast(joint_id));
    }

    pub inline fn prismaticJointEnableLimit(joint_id: JointId, enableLimit: bool) void {
        c.b2PrismaticJoint_EnableLimit(@bitCast(joint_id), enableLimit);
    }

    pub inline fn prismaticJointIsLimitEnabled(joint_id: JointId) bool {
        return c.b2PrismaticJoint_IsLimitEnabled(@bitCast(joint_id));
    }

    pub inline fn prismaticJointGetLowerLimit(joint_id: JointId) f32 {
        return c.b2PrismaticJoint_GetLowerLimit(@bitCast(joint_id));
    }

    pub inline fn prismaticJointGetUpperLimit(joint_id: JointId) f32 {
        return c.b2PrismaticJoint_GetUpperLimit(@bitCast(joint_id));
    }

    pub inline fn prismaticJointSetLimits(joint_id: JointId, lower: f32, upper: f32) void {
        c.b2PrismaticJoint_SetLimits(@bitCast(joint_id), lower, upper);
    }

    pub inline fn prismaticJointEnableMotor(joint_id: JointId, enable: bool) void {
        c.b2PrismaticJoint_EnableMotor(@bitCast(joint_id), enable);
    }

    pub inline fn prismaticJointIsMotorEnabled(joint_id: JointId) bool {
        return c.b2PrismaticJoint_IsMotorEnabled(@bitCast(joint_id));
    }

    pub inline fn prismaticJointSetMotorSpeed(joint_id: JointId, speed: f32) void {
        c.b2PrismaticJoint_SetMotorSpeed(@bitCast(joint_id), speed);
    }

    pub inline fn prismaticJointGetMotorSpeed(joint_id: JointId) f32 {
        return c.b2PrismaticJoint_GetMotorSpeed(@bitCast(joint_id));
    }

    pub inline fn prismaticJointGetMotorForce(joint_id: JointId) f32 {
        return c.b2PrismaticJoint_GetMotorForce(@bitCast(joint_id));
    }

    pub inline fn prismaticJointSetMaxMotorForce(joint_id: JointId, force: f32) void {
        c.b2PrismaticJoint_SetMaxMotorForce(@bitCast(joint_id), force);
    }

    pub inline fn prismaticJointGetMaxMotorForce(joint_id: JointId) f32 {
        return c.b2PrismaticJoint_GetMaxMotorForce(@bitCast(joint_id));
    }

    pub inline fn revoluteJointEnableSpring(joint_id: JointId, enable: bool) void {
        c.b2RevoluteJoint_EnableSpring(@bitCast(joint_id), enable);
    }

    pub inline fn revoluteJointIsSpringEnabled(joint_id: JointId) bool {
        return c.b2RevoluteJoint_IsSpringEnabled(@bitCast(joint_id));
    }

    pub inline fn revoluteJointIsLimitEnabled(joint_id: JointId) bool {
        return c.b2RevoluteJoint_IsLimitEnabled(@bitCast(joint_id));
    }

    pub inline fn revoluteJointSetSpringHertz(joint_id: JointId, hertz: f32) void {
        c.b2RevoluteJoint_SetSpringHertz(@bitCast(joint_id), hertz);
    }

    pub inline fn revoluteJointGetSpringHertz(joint_id: JointId) f32 {
        return c.b2RevoluteJoint_GetSpringHertz(@bitCast(joint_id));
    }

    pub inline fn revoluteJointSetSpringDampingRatio(joint_id: JointId, ratio: f32) void {
        c.b2RevoluteJoint_SetSpringDampingRatio(@bitCast(joint_id), ratio);
    }

    pub inline fn revoluteJointGetSpringDampingRatio(joint_id: JointId) f32 {
        return c.b2RevoluteJoint_GetSpringDampingRatio(@bitCast(joint_id));
    }

    pub inline fn revoluteJointGetAngle(joint_id: JointId) f32 {
        return c.b2RevoluteJoint_GetAngle(@bitCast(joint_id));
    }

    pub inline fn revoluteJointEnableLimit(joint_id: JointId, enable: bool) void {
        c.b2RevoluteJoint_EnableLimit(@bitCast(joint_id), enable);
    }

    pub inline fn revoluteJointGetLowerLimit(joint_id: JointId) f32 {
        return c.b2RevoluteJoint_GetLowerLimit(@bitCast(joint_id));
    }

    pub inline fn revoluteJointGetUpperLimit(joint_id: JointId) f32 {
        return c.b2RevoluteJoint_GetUpperLimit(@bitCast(joint_id));
    }

    pub inline fn revoluteJointSetLimits(joint_id: JointId, lower: f32, upper: f32) void {
        c.b2RevoluteJoint_SetLimits(@bitCast(joint_id), lower, upper);
    }

    pub inline fn revoluteJointEnableMotor(joint_id: JointId, enable: bool) void {
        c.b2RevoluteJoint_EnableMotor(@bitCast(joint_id), enable);
    }

    pub inline fn revoluteJointIsMotorEnabled(joint_id: JointId) bool {
        return c.b2RevoluteJoint_IsMotorEnabled(@bitCast(joint_id));
    }

    pub inline fn revoluteJointSetMotorSpeed(joint_id: JointId, speed: f32) void {
        c.b2RevoluteJoint_SetMotorSpeed(@bitCast(joint_id), speed);
    }

    pub inline fn revoluteJointGetMotorSpeed(joint_id: JointId) f32 {
        return c.b2RevoluteJoint_GetMotorSpeed(@bitCast(joint_id));
    }

    pub inline fn revoluteJointGetMotorTorque(joint_id: JointId) f32 {
        return c.b2RevoluteJoint_GetMotorTorque(@bitCast(joint_id));
    }

    pub inline fn revoluteJointSetMaxMotorTorque(joint_id: JointId, torque: f32) void {
        c.b2RevoluteJoint_SetMaxMotorTorque(@bitCast(joint_id), torque);
    }

    pub inline fn revoluteJointGetMaxMotorTorque(joint_id: JointId) f32 {
        return c.b2RevoluteJoint_GetMaxMotorTorque(@bitCast(joint_id));
    }

    pub inline fn wheelJointEnableSpring(joint_id: JointId, enable: bool) void {
        c.b2WheelJoint_EnableSpring(@bitCast(joint_id), enable);
    }

    pub inline fn wheelJointIsSpringEnabled(joint_id: JointId) bool {
        return c.b2WheelJoint_IsSpringEnabled(@bitCast(joint_id));
    }

    pub inline fn wheelJointSetSpringHertz(joint_id: JointId, hertz: f32) void {
        return c.b2WheelJoint_SetSpringHertz(@bitCast(joint_id), hertz);
    }

    pub inline fn wheelJointGetSpringHertz(joint_id: JointId) f32 {
        return c.b2WheelJoint_GetSpringHertz(@bitCast(joint_id));
    }

    pub inline fn wheelJointSetSpringDampingRatio(joint_id: JointId, ratio: f32) void {
        c.b2WheelJoint_SetSpringDampingRatio(@bitCast(joint_id), ratio);
    }

    pub inline fn wheelJointGetSpringDampingRatio(joint_id: JointId) f32 {
        return c.b2WheelJoint_GetSpringDampingRatio(@bitCast(joint_id));
    }

    pub inline fn wheelJointEnableLimit(joint_id: JointId, enable: bool) void {
        c.b2WheelJoint_EnableLimit(@bitCast(joint_id), enable);
    }

    pub inline fn wheelJointIsLimitEnabled(joint_id: JointId) bool {
        return c.b2WheelJoint_IsLimitEnabled(@bitCast(joint_id));
    }

    pub inline fn wheelJointGetLowerLimit(joint_id: JointId) f32 {
        return c.b2WheelJoint_GetLowerLimit(@bitCast(joint_id));
    }

    pub inline fn wheelJointGetUpperLimit(joint_id: JointId) f32 {
        return c.b2WheelJoint_GetUpperLimit(@bitCast(joint_id));
    }

    pub inline fn wheelJointSetLimits(joint_id: JointId, lower: f32, upper: f32) void {
        c.b2WheelJoint_SetLimits(@bitCast(joint_id), lower, upper);
    }

    pub inline fn wheelJointEnableMotor(joint_id: JointId, enable: bool) void {
        c.b2WheelJoint_EnableMotor(@bitCast(joint_id), enable);
    }

    pub inline fn wheelJointIsMotorEnabled(joint_id: JointId) bool {
        return c.b2WheelJoint_IsMotorEnabled(@bitCast(joint_id));
    }

    pub inline fn wheelJointSetMotorSpeed(joint_id: JointId, speed: f32) void {
        c.b2WheelJoint_SetMotorSpeed(@bitCast(joint_id), speed);
    }

    pub inline fn wheelJointGetMotorSpeed(joint_id: JointId) f32 {
        return c.b2WheelJoint_GetMotorSpeed(@bitCast(joint_id));
    }

    pub inline fn wheelJointGetMotorTorque(joint_id: JointId) f32 {
        return c.b2WheelJoint_GetMotorTorque(@bitCast(joint_id));
    }

    pub inline fn wheelJointSetMaxMotorTorque(joint_id: JointId, torque: f32) void {
        c.b2WheelJoint_SetMaxMotorTorque(@bitCast(joint_id), torque);
    }

    pub inline fn wheelJointGetMaxMotorTorque(joint_id: JointId) f32 {
        return c.b2WheelJoint_GetMaxMotorTorque(@bitCast(joint_id));
    }

    pub inline fn weldJointSetLinearHertz(joint_id: JointId, hertz: f32) void {
        return c.b2WeldJoint_SetLinearHertz(@bitCast(joint_id), hertz);
    }

    pub inline fn weldJointGetLinearHertz(joint_id: JointId) f32 {
        return c.b2WeldJoint_GetLinearHertz(@bitCast(joint_id));
    }

    pub inline fn weldJointSetLinearDampingRatio(joint_id: JointId, ratio: f32) void {
        c.b2WeldJoint_SetLinearDampingRatio(@bitCast(joint_id), ratio);
    }

    pub inline fn weldJointGetLinearDampingRatio(joint_id: JointId) f32 {
        return c.b2WeldJoint_GetLinearDampingRatio(@bitCast(joint_id));
    }

    pub inline fn weldJointSetAngularHertz(joint_id: JointId, hertz: f32) void {
        return c.b2WeldJoint_SetAngularHertz(@bitCast(joint_id), hertz);
    }

    pub inline fn weldJointGetAngularHertz(joint_id: JointId) f32 {
        return c.b2WeldJoint_GetAngularHertz(@bitCast(joint_id));
    }

    pub inline fn weldJointSetAngularDampingRatio(joint_id: JointId, ratio: f32) void {
        c.b2WeldJoint_SetAngularDampingRatio(@bitCast(joint_id), ratio);
    }

    pub inline fn weldJointGetAngularDampingRatio(joint_id: JointId) f32 {
        return c.b2WeldJoint_GetAngularDampingRatio(@bitCast(joint_id));
    }
};

pub const ChainId = extern struct {
    index: i32,
    world_0: u16,
    revision: u16,

    pub inline fn create(body_id: BodyId, def: ChainDef) ChainId {
        return @bitCast(c.b2CreateChain(@bitCast(body_id), @ptrCast(&def)));
    }

    pub inline fn destroy(chain_id: ChainId) void {
        c.b2DestroyChain(@bitCast(chain_id));
    }

    pub inline fn setFriction(chain_id: ChainId, friction: f32) void {
        c.b2Chain_SetFriction(@bitCast(chain_id), friction);
    }

    pub inline fn setRestitution(chain_id: ChainId, restitution: f32) void {
        c.b2Chain_SetRestitution(@bitCast(chain_id), restitution);
    }

    pub inline fn isValid(chain_id: ChainId) bool {
        return c.b2Chain_IsValid(@bitCast(chain_id));
    }
};

pub const ShapeId = extern struct {
    index_1: i32,
    world_0: u16,
    revision: u16,

    pub inline fn createCircleShape(body_id: BodyId, def: ShapeDef, circle: Circle) ShapeId {
        return @bitCast(c.b2CreateCircleShape(@bitCast(body_id), @ptrCast(&def), @ptrCast(&circle)));
    }

    pub inline fn createSegmentShape(body_id: BodyId, def: ShapeDef, segment: Segment) ShapeId {
        return @bitCast(c.b2CreateSegmentShape(@bitCast(body_id), @ptrCast(&def), @ptrCast(&segment)));
    }

    pub inline fn createCapsuleShape(body_id: BodyId, def: ShapeDef, capsule: Capsule) ShapeId {
        return @bitCast(c.b2CreateCapsuleShape(@bitCast(body_id), @ptrCast(&def), @ptrCast(&capsule)));
    }

    pub inline fn createPolygonShape(body_id: BodyId, def: ShapeDef, polygon: Polygon) ShapeId {
        return @bitCast(c.b2CreatePolygonShape(@bitCast(body_id), @ptrCast(&def), @ptrCast(&polygon)));
    }

    pub inline fn destroy(shape_id: ShapeId) void {
        c.b2DestroyShape(@bitCast(shape_id));
    }

    pub inline fn isValid(shape_id: ShapeId) bool {
        return c.b2Shape_IsValid(@bitCast(shape_id));
    }

    pub inline fn getType(shape_id: ShapeId) ShapeType {
        return @bitCast(c.b2Shape_GetType(@bitCast(shape_id)));
    }

    pub inline fn getBody(shape_id: ShapeId) BodyId {
        return @bitCast(c.b2Shape_GetBody(@bitCast(shape_id)));
    }

    pub inline fn isSensor(shape_id: ShapeId) bool {
        return c.b2Shape_IsSensor(@bitCast(shape_id));
    }

    pub inline fn setUserData(shape_id: ShapeId, user_data: ?*anyopaque) void {
        c.b2Shape_SetUserData(@bitCast(shape_id), @ptrCast(user_data));
    }

    pub inline fn getUserData(shape_id: ShapeId) ?*anyopaque {
        return @ptrCast(c.b2Shape_GetUserData(@bitCast(shape_id)));
    }

    pub inline fn setDensity(shape_id: ShapeId, density: f32) void {
        c.b2Shape_SetDensity(@bitCast(shape_id), density);
    }

    pub inline fn getDensity(shape_id: ShapeId) f32 {
        return c.b2Shape_GetDensity(@bitCast(shape_id));
    }

    pub inline fn setFriction(shape_id: ShapeId, friction: f32) void {
        c.b2Shape_SetFriction(@bitCast(shape_id), friction);
    }

    pub inline fn getFriction(shape_id: ShapeId) f32 {
        return c.b2Shape_GetFriction(@bitCast(shape_id));
    }

    pub inline fn setRestitution(shape_id: ShapeId, restitution: f32) void {
        c.b2Shape_SetRestitution(@bitCast(shape_id), restitution);
    }

    pub inline fn getRestitution(shape_id: ShapeId) f32 {
        return c.b2Shape_GetRestitution(@bitCast(shape_id));
    }

    pub inline fn getFilter(shape_id: ShapeId) Filter {
        return @bitCast(c.b2Shape_GetFilter(@bitCast(shape_id)));
    }

    pub inline fn setFilter(shape_id: ShapeId, filter: Filter) void {
        c.b2Shape_SetFilter(@bitCast(shape_id), @bitCast(filter));
    }

    pub inline fn enableSensorEvents(shape_id: ShapeId, flag: bool) void {
        c.b2Shape_EnableSensorEvents(@bitCast(shape_id), flag);
    }

    pub inline fn areSensorEventsEnabled(shape_id: ShapeId) bool {
        return c.b2Shape_AreSensorEventsEnabled(@bitCast(shape_id));
    }

    pub inline fn enableContactEvents(shape_id: ShapeId, flag: bool) void {
        c.b2Shape_EnableContactEvents(@bitCast(shape_id), flag);
    }

    pub inline fn areContactEventsEnabled(shape_id: ShapeId) bool {
        c.b2Shape_AreContactEventsEnabled(@bitCast(shape_id));
    }

    pub inline fn enablePreSolveEvents(shape_id: ShapeId, flag: bool) void {
        c.b2Shape_EnablePreSolveEvents(@bitCast(shape_id), flag);
    }

    pub inline fn arePreSolveEventsEnabled(shape_id: ShapeId) bool {
        return c.b2Shape_ArePreSolveEventsEnabled(@bitCast(shape_id));
    }

    pub inline fn enableHitEvents(shape_id: ShapeId, flag: bool) void {
        c.b2Shape_EnableContactEvents(@bitCast(shape_id), flag);
    }

    pub inline fn areHitEventsEnabled(shape_id: ShapeId) bool {
        return c.b2Shape_AreHitEventsEnabled(@bitCast(shape_id));
    }

    pub inline fn testPoint(shape_id: ShapeId, point: Vec2) bool {
        return c.b2Shape_TestPoint(@bitCast(shape_id), @bitCast(point));
    }

    pub inline fn rayCast(shape_id: ShapeId, input: RayCastInput) CastOutput {
        return @bitCast(c.b2Shape_RayCast(@bitCast(shape_id), @ptrCast(&input)));
    }

    pub inline fn getCircle(shape_id: ShapeId) Circle {
        return @bitCast(c.b2Shape_GetCircle(@bitCast(shape_id)));
    }

    pub inline fn getSegment(shape_id: ShapeId) Segment {
        return @bitCast(c.b2Shape_GetSegment(@bitCast(shape_id)));
    }

    pub inline fn getChainSegment(shape_id: ShapeId) ChainSegment {
        return @bitCast(c.b2Shape_GetChainSegment(@bitCast(shape_id)));
    }

    pub inline fn getCapsule(shape_id: ShapeId) Capsule {
        return @bitCast(c.b2Shape_GetCapsule(@bitCast(shape_id)));
    }

    pub inline fn getPolygon(shape_id: ShapeId) Polygon {
        return @bitCast(c.b2Shape_GetPolygon(@bitCast(shape_id)));
    }

    pub inline fn setCircle(shape_id: ShapeId, circle: Circle) void {
        c.b2Shape_SetCircle(@bitCast(shape_id), @bitCast(circle));
    }

    pub inline fn setCapsule(shape_id: ShapeId, capsule: Capsule) void {
        c.b2Shape_SetCapsule(@bitCast(shape_id), @bitCast(capsule));
    }

    pub inline fn setSegment(shape_id: ShapeId, segment: Segment) void {
        c.b2Shape_SetSegment(@bitCast(shape_id), @bitCast(segment));
    }

    pub inline fn setPolygon(shape_id: ShapeId, polygon: Polygon) void {
        c.b2Shape_SetPolygon(@bitCast(shape_id), @bitCast(polygon));
    }

    pub inline fn getParentChain(shape_id: ShapeId) ChainId {
        return @bitCast(c.b2Shape_GetParentChain(@bitCast(shape_id)));
    }

    pub inline fn getContactCapacity(shape_id: ShapeId) usize {
        return @intCast(c.b2Shape_GetContactCapacity(@bitCast(shape_id)));
    }

    pub inline fn getContactData(shape_id: ShapeId, contacts: []ContactData) usize {
        return @intCast(c.b2Shape_GetContactData(@bitCast(shape_id), @ptrCast(contacts.ptr), @intCast(contacts.len)));
    }

    pub inline fn getAABB(shape_id: ShapeId) AABB {
        return @bitCast(c.b2Shape_GetAABB(@bitCast(shape_id)));
    }

    pub inline fn getClosestPoint(shape_id: ShapeId, target: Vec2) Vec2 {
        return @bitCast(c.b2Shape_GetClosestPoint(@bitCast(shape_id), @bitCast(target)));
    }
};

pub const BodyId = extern struct {
    index_1: i32,
    world_0: u16,
    revision: u16,

    pub inline fn create(world_id: WorldId, def: BodyDef) BodyId {
        return @bitCast(c.b2CreateBody(@bitCast(world_id), @ptrCast(&def)));
    }

    pub inline fn destroy(body_id: BodyId) void {
        return c.b2DestroyBody(@bitCast(body_id));
    }

    pub inline fn isValid(id: BodyId) bool {
        return c.b2Body_IsValid(@bitCast(id));
    }

    pub inline fn getType(body_id: BodyId) BodyType {
        return @bitCast(c.b2Body_GetType(@bitCast(body_id)));
    }

    pub inline fn setType(body_id: BodyId, @"type": BodyType) void {
        c.b2Body_SetType(@bitCast(body_id), @bitCast(@"type"));
    }

    pub inline fn setUserData(body_id: BodyId, user_data: ?*anyopaque) void {
        c.b2Body_SetUserData(@bitCast(body_id), @ptrCast(user_data));
    }

    pub inline fn getUserData(body_id: BodyId) ?*anyopaque {
        return @ptrCast(c.b2Body_GetUserData(@bitCast(body_id)));
    }

    pub inline fn getPosition(body_id: BodyId) Vec2 {
        return @bitCast(c.b2Body_GetPosition(@bitCast(body_id)));
    }

    pub inline fn getRotation(body_id: BodyId) Rot {
        return @bitCast(c.b2Body_GetRotation(@bitCast(body_id)));
    }

    pub inline fn getAngle(body_id: BodyId) f32 {
        return c.b2Body_GetAngle(@bitCast(body_id));
    }

    pub inline fn getTransform(body_id: BodyId) Transform {
        return @bitCast(c.b2Body_GetTransform(@bitCast(body_id)));
    }

    pub inline fn setTransform(body_id: BodyId, position: Vec2, angle: f32) void {
        c.b2Body_SetTransform(@bitCast(body_id), @bitCast(position), angle);
    }

    pub inline fn getLocalPoint(body_id: BodyId, world_point: Vec2) Vec2 {
        return @bitCast(c.b2Body_GetLocalPoint(@bitCast(body_id), @bitCast(world_point)));
    }

    pub inline fn getWorldPoint(body_id: BodyId, local_point: Vec2) Vec2 {
        return @bitCast(c.b2Body_GetWorldPoint(@bitCast(body_id), @bitCast(local_point)));
    }

    pub inline fn getLocalVector(body_id: BodyId, world_vector: Vec2) Vec2 {
        return @bitCast(c.b2Body_GetLocalVector(@bitCast(body_id), @bitCast(world_vector)));
    }

    pub inline fn getWorldVector(body_id: BodyId, local_vector: Vec2) Vec2 {
        return @bitCast(c.b2Body_GetWorldVector(@bitCast(body_id), @bitCast(local_vector)));
    }

    pub inline fn getLinearVelocity(body_id: BodyId) Vec2 {
        return @bitCast(c.b2Body_GetLinearVelocity(@bitCast(body_id)));
    }

    pub inline fn getAngularVelocity(body_id: BodyId) f32 {
        return c.b2Body_GetAngularVelocity(@bitCast(body_id));
    }

    pub inline fn setLinearVelocity(body_id: BodyId, linear_velocity: Vec2) void {
        c.b2Body_SetLinearVelocity(@bitCast(body_id), @bitCast(linear_velocity));
    }

    pub inline fn setAngularVelocity(body_id: BodyId, angular_velocity: f32) void {
        c.b2Body_SetAngularVelocity(@bitCast(body_id), @bitCast(angular_velocity));
    }

    pub inline fn applyForce(body_id: BodyId, force: Vec2, point: Vec2, wake: bool) void {
        c.b2Body_ApplyForce(@bitCast(body_id), @bitCast(force), @bitCast(point), wake);
    }

    pub inline fn applyForceToCenter(body_id: BodyId, force: Vec2, wake: bool) void {
        c.b2Body_ApplyForceToCenter(@bitCast(body_id), @bitCast(force), wake);
    }

    pub inline fn applyTorque(body_id: BodyId, torque: f32, wake: bool) void {
        c.b2Body_ApplyTorque(@bitCast(body_id), @bitCast(torque), @bitCast(wake));
    }

    pub inline fn applyLinearImpulse(body_id: BodyId, impulse: Vec2, point: Vec2, wake: bool) void {
        c.b2Body_ApplyLinearImpulse(@bitCast(body_id), @bitCast(impulse), @bitCast(point), @bitCast(wake));
    }

    pub inline fn applyLinearImpulseToCenter(body_id: BodyId, impulse: Vec2, wake: bool) void {
        c.b2Body_ApplyLinearImpulseToCenter(@bitCast(body_id), @bitCast(impulse), wake);
    }

    pub inline fn applyAngularImpulse(body_id: BodyId, impulse: f32, wake: bool) void {
        c.b2Body_ApplyAngularImpulse(@bitCast(body_id), @bitCast(impulse), wake);
    }

    pub inline fn getMass(body_id: BodyId) f32 {
        return c.b2Body_GetMass(@bitCast(body_id));
    }

    pub inline fn getRotationalInertia(body_id: BodyId) f32 {
        return c.b2Body_GetRotationalIntertia(@bitCast(body_id));
    }

    pub inline fn getLocalCenterOfMass(body_id: BodyId) Vec2 {
        return @bitCast(c.b2Body_GetLocalCenterOfMass(@bitCast(body_id)));
    }

    pub inline fn getWorldCenterOfMass(body_id: BodyId) Vec2 {
        return @bitCast(c.b2Body_GetWorldCenterOfMass(@bitCast(body_id)));
    }

    pub inline fn setMassData(body_id: BodyId, mass_data: MassData) void {
        c.b2Body_SetMassData(@bitCast(body_id), @bitCast(mass_data));
    }

    pub inline fn getMassData(body_id: BodyId) MassData {
        return @bitCast(c.b2Body_GetMassData(@bitCast(body_id)));
    }

    pub inline fn applyMassFromShapes(body_id: BodyId) void {
        c.b2Body_ApplyMassFromShapes(@bitCast(body_id));
    }

    pub inline fn setAutomaticMass(body_id: BodyId, automatic_mass: bool) void {
        c.b2Body_SetAutomaticMass(@bitCast(body_id), automatic_mass);
    }

    pub inline fn getAutomaticMass(body_id: BodyId) bool {
        return c.b2Body_GetAutomaticMass(@bitCast(body_id));
    }

    pub inline fn setLinearDamping(body_id: BodyId, linear_damping: f32) void {
        c.b2Body_SetLinearDamping(@bitCast(body_id), linear_damping);
    }

    pub inline fn getLinearDamping(body_id: BodyId) f32 {
        return c.b2Body_GetLinearDamping(@bitCast(body_id));
    }

    pub inline fn setAngularDamping(body_id: BodyId, angular_damping: f32) void {
        c.b2Body_SetAngularDamping(@bitCast(body_id), angular_damping);
    }

    pub inline fn getAngularDamping(body_id: BodyId) f32 {
        return c.b2Body_GetAngularDamping(@bitCast(body_id));
    }

    pub inline fn setGravityScale(body_id: BodyId, gravity_scale: f32) void {
        c.b2Body_SetGravityScale(@bitCast(body_id), gravity_scale);
    }

    pub inline fn getGravityScale(body_id: BodyId) f32 {
        return c.b2Body_GetGravityScale(@bitCast(body_id));
    }

    pub inline fn isAwake(body_id: BodyId) bool {
        return c.b2Body_IsAwake(@bitCast(body_id));
    }

    pub inline fn setAwake(body_id: BodyId, awake: bool) void {
        c.b2Body_SetAwake(@bitCast(body_id), awake);
    }

    pub inline fn enableSleep(body_id: BodyId, enable_sleep: bool) void {
        c.b2Body_EnableSleep(@bitCast(body_id), enable_sleep);
    }

    pub inline fn isSleepEnabled(body_id: BodyId) bool {
        return c.b2Body_IsSleepEnabled(@bitCast(body_id));
    }

    pub inline fn setSleepThreshold(body_id: BodyId, sleep_threshold: f32) void {
        c.b2Body_SetSleepThreshold(@bitCast(body_id), sleep_threshold);
    }

    pub inline fn getSleepThreshold(body_id: BodyId) f32 {
        return c.b2Body_GetSleepThreshold(@bitCast(body_id));
    }

    pub inline fn isEnabled(body_id: BodyId) bool {
        return c.b2Body_IsEnabled(@bitCast(body_id));
    }

    pub inline fn disable(body_id: BodyId) void {
        c.b2Body_Disable(@bitCast(body_id));
    }

    pub inline fn enable(body_id: BodyId) void {
        c.b2Body_Enable(@bitCast(body_id));
    }

    pub inline fn setFixedRotation(body_id: BodyId, flag: bool) void {
        c.b2Body_SetFixedRotation(@bitCast(body_id), flag);
    }

    pub inline fn isFixedRotation(body_id: BodyId) bool {
        return c.b2Body_IsFixedRotation(@bitCast(body_id));
    }

    pub inline fn setBullet(body_id: BodyId, flag: bool) void {
        c.b2Body_SetBullet(@bitCast(body_id), flag);
    }

    pub inline fn isBullet(body_id: BodyId) bool {
        return c.b2Body_IsBullet(@bitCast(body_id));
    }

    pub inline fn enableHitEvents(body_id: BodyId, enable_hit_events: bool) void {
        c.b2Body_EnableHitEvents(@bitCast(body_id), enable_hit_events);
    }

    pub inline fn getShapeCount(body_id: BodyId) usize {
        return @intCast(c.b2Body_GetShapeCount(@bitCast(body_id)));
    }

    pub inline fn getShapes(body_id: BodyId, shapes: []ShapeId) usize {
        return @intCast(c.b2Body_GetShapes(@bitCast(body_id), @ptrCast(shapes.ptr), @intCast(shapes.len)));
    }

    pub inline fn getJointCount(body_id: BodyId) usize {
        return @intCast(c.b2Body_GetJointCount(body_id));
    }

    pub inline fn getJoints(body_id: BodyId, joints: []JointId) usize {
        return @intCast(c.b2Body_GetJoints(@bitCast(body_id), @ptrCast(joints.ptr), @intCast(joints.len)));
    }

    pub inline fn getContactCapacity(body_id: BodyId) usize {
        return @intCast(c.b2Body_GetContactCapacity(@bitCast(body_id)));
    }

    pub inline fn getContactData(body_id: BodyId, contacts: []ContactData) usize {
        return @intCast(c.b2Body_GetContactData(@bitCast(body_id), @ptrCast(contacts.ptr), @intCast(contacts.len)));
    }

    pub inline fn computeAABB(body_id: BodyId) AABB {
        return @bitCast(c.b2Body_ComputeAABB(@bitCast(body_id)));
    }
};

pub const Hull = extern struct {
    points: [8]Vec2,
    count: i32,

    pub inline fn makePolygon(hull: Hull, radius: f32) Polygon {
        return @bitCast(c.b2MakePolygon(@ptrCast(&hull), radius));
    }

    pub inline fn makeOffsetPolygon(hull: Hull, radius: f32, transform: Transform) Polygon {
        return @bitCast(c.b2MakeOffsetPolygon(@ptrCast(&hull), radius, @bitCast(transform)));
    }

    pub inline fn compute(points: []const Vec2) Hull {
        return @bitCast(c.b2ComputeHull(@ptrCast(points.ptr), @intCast(points.len)));
    }

    pub inline fn validate(hull: Hull) bool {
        return c.b2ValidateHull(@ptrCast(&hull));
    }
};

pub const Capsule = extern struct {
    center_1: Vec2,
    center_2: Vec2,
    radius: f32,

    pub inline fn containsPoint(shape: Capsule, point: Vec2) bool {
        return c.b2PointInCapsule(@bitCast(point), @ptrCast(&shape));
    }

    pub inline fn computeAABB(shape: Capsule, transform: Transform) AABB {
        return @bitCast(c.b2ComputeCapsuleAABB(@ptrCast(&shape), @bitCast(transform)));
    }

    pub inline fn computeMass(shape: Capsule, density: f32) MassData {
        return @bitCast(c.b2ComputeCapsuleMass(@ptrCast(&shape), density));
    }

    pub inline fn rayCast(self: Capsule, input: RayCastInput) CastOutput {
        return @bitCast(c.b2RayCastCapsule(@ptrCast(&input), @ptrCast(&self)));
    }

    pub inline fn shapeCast(self: Capsule, input: ShapeCastInput) CastOutput {
        return @bitCast(c.b2ShapeCastCapsule(@ptrCast(&input), @ptrCast(&self)));
    }
};

pub const Polygon = extern struct {
    vertices: [max_polygon_vertices]Vec2,
    normals: [max_polygon_vertices]Vec2,
    centroid: Vec2,
    radius: f32,
    count: i32,

    pub inline fn containsPoint(shape: Polygon, point: Vec2) bool {
        return c.b2PointInPolygon(@bitCast(point), @ptrCast(&shape));
    }

    pub inline fn computeAABB(shape: Polygon, tfm: Transform) AABB {
        return @bitCast(c.b2ComputePolygonAABB(@ptrCast(&shape), @bitCast(tfm)));
    }

    pub inline fn computeMass(shape: Polygon, density: f32) MassData {
        return @bitCast(c.b2ComputePolygonMass(@ptrCast(&shape), density));
    }

    pub inline fn transform(polygon: Polygon, tfm: Transform) Polygon {
        return @bitCast(c.b2TransformPolygon(@bitCast(tfm), @ptrCast(&polygon)));
    }

    pub inline fn rayCast(self: Polygon, input: RayCastInput) CastOutput {
        return @bitCast(c.b2RayCastPolygon(@ptrCast(&input), @ptrCast(&self)));
    }

    pub inline fn shapeCast(self: Polygon, input: ShapeCastInput) CastOutput {
        return @bitCast(c.b2ShapeCastPolygon(@ptrCast(&input), @ptrCast(&self)));
    }
};

pub const CastOutput = extern struct {
    normal: Vec2,
    point: Vec2,
    fraction: f32,
    iterations: i32,
    hit: bool,
};

pub const SegmentDistanceResult = extern struct {
    closest_1: Vec2,
    closest_2: Vec2,
    fraction_1: f32,
    fraction_2: f32,
    distance_squared: f32,
};

pub const DistanceCache = extern struct {
    count: u16,
    index_a: [3]u8,
    index_b: [3]u8,
};

pub const DistanceInput = extern struct {
    proxy_a: DistanceProxy,
    proxy_b: DistanceProxy,
    transform_a: Transform,
    transform_b: Transform,
    use_radii: bool,
};

pub const DistanceOutput = extern struct {
    point_a: Vec2,
    point_b: Vec2,
    distance: f32,
    iterations: i32,
    simplex_count: i32,
};

pub const ShapeCastPairInput = extern struct {
    proxy_a: DistanceProxy,
    proxy_b: DistanceProxy,
    transform_a: Transform,
    transform_b: Transform,
    translation_b: Vec2,
    max_fraction: f32,

    pub inline fn cast(input: ShapeCastPairInput) CastOutput {
        return @bitCast(c.b2ShapeCast(@ptrCast(&input)));
    }
};

pub const DistanceProxy = extern struct {
    points: [max_polygon_vertices]Vec2,
    count: i32,
    radius: f32,

    pub inline fn make(vertices: []const Vec2, radius: f32) DistanceProxy {
        return @bitCast(c.b2MakeProxy(@ptrCast(vertices.ptr), @intCast(vertices.len), radius));
    }
};

pub const Sweep = extern struct {
    local_center: Vec2,
    c1: Vec2,
    c2: Vec2,
    q1: Rot,
    q2: Rot,

    pub inline fn getTransform(sweep: Sweep, time: f32) Transform {
        return @bitCast(c.b2GetSweepTransform(@ptrCast(&sweep), time));
    }
};

pub const RayCastInput = extern struct {
    origin: Vec2,
    translation: Vec2,
    max_fraction: f32,

    pub inline fn isValid(input: RayCastInput) bool {
        return c.b2IsValidRay(@ptrCast(&input));
    }
};

pub const ShapeCastInput = extern struct {
    points: [max_polygon_vertices]Vec2,
    count: i32,
    radius: f32,
    translation: Vec2,
    max_fraction: f32,
};

pub const BodyMoveEvent = extern struct {
    transform: Transform,
    body_id: BodyId,
    user_data: ?*anyopaque,
    fell_asleep: bool,
};

pub const BodyEvents = extern struct {
    move_events: [*]BodyMoveEvent,
    move_count: i32,
};

pub const SensorEndTouchEvent = extern struct {
    sensor_shape_id: ShapeId,
    visitor_shape_id: ShapeId,
};

pub const SensorBeginTouchEvent = extern struct {
    sensor_shape_id: ShapeId,
    visitor_shape_id: ShapeId,
};

pub const SensorEvents = extern struct {
    begin_events: [*]SensorBeginTouchEvent,
    end_events: [*]SensorEndTouchEvent,
    begin_count: i32,
    end_count: i32,
};

pub const ContactBeginTouchEvent = extern struct {
    shape_id_a: ShapeId,
    shape_id_b: ShapeId,
};

pub const ContactEndTouchEvent = extern struct {
    shape_id_a: ShapeId,
    shape_id_b: ShapeId,
};

pub const ContactHitEvent = extern struct {
    shape_id_a: ShapeId,
    shape_id_b: ShapeId,
    point: Vec2,
    normal: Vec2,
    approach_speed: f32,
};

pub const ContactEvents = extern struct {
    begin_events: [*]ContactBeginTouchEvent,
    end_events: [*]ContactEndTouchEvent,
    hit_events: [*]ContactHitEvent,
    begin_count: i32,
    end_count: i32,
    hit_count: i32,
};

pub const ToiInput = extern struct {
    proxy_a: DistanceProxy,
    proxy_b: DistanceProxy,
    sweep_a: Sweep,
    sweep_b: Sweep,
    t_max: f32,

    pub inline fn timeOfImpact(input: ToiInput) ToiOutput {
        return c.b2TimeOfImpact(@ptrCast(&input));
    }
};

pub const ToiOutput = extern struct {
    state: ToiState,
    t: f32,
};

pub const ToiState = enum(i32) {
    unknown,
    failed,
    overlapped,
    hit,
    separated,
};

pub const TreeNode = extern struct {
    aabb: AABB,
    category_bits: u64,
    anon_union: extern union {
        parent: i32,
        next: i32,
    },
    child_1: i32,
    child_2: i32,
    user_data: i32,
    height: i16,
    enlarged: bool,
    pad: [5]u8,
};

pub const SimplexVertex = extern struct {
    w_a: Vec2,
    w_b: Vec2,
    w: Vec2,
    a: f32,
    index_a: i32,
    index_b: i32,
};

pub const Simplex = extern struct {
    v1: SimplexVertex,
    v2: SimplexVertex,
    v3: SimplexVertex,
    coint: i32,
};

pub const ManifoldPoint = extern struct {
    point: Vec2,
    anchor_a: Vec2,
    anchor_b: Vec2,
    separation: f32,
    normal_impulse: f32,
    tangent_impulse: f32,
    max_normal_impulse: f32,
    normal_velocity: f32,
    id: u16,
    persisted: bool,
};

pub const Manifold = extern struct {
    points: [2]ManifoldPoint,
    normal: Vec2,
    point_count: i32,
};

pub const RayResult = extern struct {
    shape_id: ShapeId,
    point: Vec2,
    normal: Vec2,
    fraction: f32,
    hit: bool,
};

pub const Circle = extern struct {
    center: Vec2,
    radius: f32,

    pub inline fn containsPoint(shape: Circle, point: Vec2) bool {
        return c.b2PointInCircle(@bitCast(point), @ptrCast(&shape));
    }

    pub inline fn computeAABB(shape: Circle, transform: Transform) AABB {
        return @bitCast(c.b2ComputeCircleAABB(@ptrCast(&shape), @bitCast(transform)));
    }

    pub inline fn computeMass(shape: Circle, density: f32) MassData {
        return @bitCast(c.b2ComputeCircleMass(@ptrCast(&shape), density));
    }

    pub inline fn rayCast(self: Circle, input: RayCastInput) CastOutput {
        return @bitCast(c.b2RayCastCircle(@ptrCast(&input), @ptrCast(&self)));
    }

    pub inline fn shapeCast(self: Circle, input: ShapeCastInput) CastOutput {
        return @bitCast(c.b2ShapeCastCircle(@ptrCast(&input), @ptrCast(&self)));
    }
};

pub const Filter = extern struct {
    category_bits: u64,
    mask_bits: u64,
    group_index: i32,

    pub inline fn default() Filter {
        return @bitCast(c.b2DefaultFilter());
    }
};

pub const DynamicTree = extern struct {
    nodes: [*]TreeNode,
    root: i32,
    node_count: i32,
    node_capacity: i32,
    free_list: i32,
    proxy_count: i32,
    leaf_indices: [*]i32,
    leaf_boxes: [*]AABB,
    leaf_centers: [*]Vec2,
    bin_indices: [*]i32,
    rebuild_capacity: i32,

    pub inline fn create() DynamicTree {
        return @bitCast(c.b2DynamicTree_Create());
    }

    pub inline fn destroy(tree: *DynamicTree) void {
        c.b2DynamicTree_Destroy(@ptrCast(tree));
    }

    pub inline fn createProxy(tree: *DynamicTree, aabb: AABB, category_bits: u64, user_data: i32) i32 {
        return c.b2DynamicTree_CreateProxy(@ptrCast(tree), @bitCast(aabb), category_bits, user_data);
    }

    pub inline fn destroyProxy(tree: *DynamicTree, proxy_id: i32) void {
        c.b2DynamicTree_DestroyProxy(@ptrCast(tree), proxy_id);
    }

    pub inline fn clone(out_tree: *DynamicTree, in_tree: *const DynamicTree) void {
        c.b2DynamicTree_Clone(@ptrCast(out_tree), @ptrCast(in_tree));
    }

    pub inline fn moveProxy(tree: *DynamicTree, proxy_id: i32, aabb: AABB) void {
        c.b2DynamicTree_MoveProxy(@ptrCast(tree), proxy_id, @bitCast(aabb));
    }

    pub inline fn enlargeProxy(tree: *DynamicTree, proxy_id: i32, aabb: AABB) void {
        c.b2DynamicTree_EnlargeProxy(@ptrCast(tree), proxy_id, @bitCast(aabb));
    }

    pub inline fn query(tree: DynamicTree, aabb: AABB, mask_bits: u64, callback: ?*const treeQueryCallback, context: ?*anyopaque) void {
        c.b2DynamicTree_Query(@ptrCast(&tree), @bitCast(aabb), mask_bits, @ptrCast(callback), @ptrCast(context));
    }

    pub inline fn rayCast(tree: DynamicTree, input: RayCastInput, mask_bits: u64, callback: ?*const treeRayCastCallback, context: ?*anyopaque) void {
        c.b2DynamicTree_RayCast(@ptrCast(&tree), @bitCast(&input), mask_bits, @ptrCast(callback), @ptrCast(context));
    }

    pub inline fn shapeCast(tree: DynamicTree, input: ShapeCastInput, mask_bits: u64, callback: ?*const treeShapeCastCallback, context: ?*anyopaque) void {
        c.b2DynamicTree_ShapeCast(@ptrCast(&tree), @ptrCast(&input), mask_bits, @ptrCast(callback), @ptrCast(context));
    }

    pub inline fn validate(tree: DynamicTree) void {
        c.b2DynamicTree_Validate(@ptrCast(&tree));
    }

    pub inline fn getHeight(tree: DynamicTree) i32 {
        return c.b2DynamicTree_GetHeight(@ptrCast(&tree));
    }

    pub inline fn getMaxBalance(tree: DynamicTree) i32 {
        return c.b2DynamicTree_GetMaxBalance(@ptrCast(&tree));
    }

    pub inline fn getAreaRatio(tree: DynamicTree) f32 {
        return c.b2DynamicTree_GetAreaRatio(@ptrCast(&tree));
    }

    pub inline fn rebuildBottomUp(tree: *DynamicTree) void {
        c.b2DynamicTree_RebuildBottomUp(@ptrCast(tree));
    }

    pub inline fn getProxyCount(tree: DynamicTree) i32 {
        return c.b2DynamicTree_GetProxyCount(@ptrCast(&tree));
    }

    pub inline fn rebuild(tree: *DynamicTree, full_build: bool) i32 {
        return c.b2DynamicTree_Rebuild(@ptrCast(tree), full_build);
    }

    pub inline fn shiftOrigin(tree: *DynamicTree, new_origin: Vec2) void {
        c.b2DynamicTree_ShiftOrigin(@ptrCast(tree), @bitCast(new_origin));
    }

    pub inline fn getByteCount(tree: DynamicTree) usize {
        return @intCast(c.b2DynamicTree_GetByteCount(@ptrCast(&tree)));
    }

    pub inline fn getUserData(tree: DynamicTree, proxy_id: i32) i32 {
        return tree.nodes[proxy_id].user_data;
    }

    pub inline fn getAABB(tree: DynamicTree, proxy_id: i32) AABB {
        return tree.nodes[proxy_id].aabb;
    }
};

pub const AABB = extern struct {
    lower_bound: Vec2,
    upper_bound: Vec2,

    pub inline fn contains(a: AABB, b: AABB) bool {
        return (a.lower_bound.x <= b.lower_bound.x) and
            (a.lower_bound.y <= b.lower_bound.y) and
            (b.upper_bound.x <= a.upper_bound.x) and
            (b.upper_bound.y <= a.upper_bound.y);
    }

    pub inline fn center(a: AABB) Vec2 {
        return .{
            .x = 0.5 * (a.lower_bound.x + a.upper_bound.x),
            .y = 0.5 * (a.lower_bound.y + a.upper_bound.y),
        };
    }

    pub inline fn extents(a: AABB) Vec2 {
        return .{
            .x = 0.5 * (a.upper_bound.x - a.lower_bound.x),
            .y = 0.5 * (a.upper_bound.y - a.lower_bound.y),
        };
    }

    pub inline fn @"union"(a: AABB, b: AABB) AABB {
        return .{
            .lower_bound = .{
                .x = @min(a.lower_bound.x, b.lower_bound.x),
                .y = @min(a.lower_bound.y, b.lower_bound.y),
            },
            .upper_bound = .{
                .x = @max(a.upper_bound.x, b.upper_bound.x),
                .y = @max(a.upper_bound.y, b.upper_bound.y),
            },
        };
    }

    pub inline fn isValid(aabb: AABB) bool {
        return c.b2AABB_IsValid(@bitCast(aabb));
    }
};

pub const QueryFilter = extern struct {
    category_bits: u64,
    mask_bits: u64,

    pub inline fn default() QueryFilter {
        return @bitCast(c.b2DefaultQueryFilter());
    }
};

pub inline fn makeSquare(h: f32) Polygon {
    return @bitCast(c.b2MakeSquare(h));
}

pub inline fn makeBox(hx: f32, hy: f32) Polygon {
    return @bitCast(c.b2MakeBox(hx, hy));
}

pub inline fn makeRoundedBox(hx: f32, hy: f32, radius: f32) Polygon {
    return @bitCast(c.b2MakeRoundedBox(hx, hy, radius));
}

pub inline fn makeOffsetBox(hx: f32, hy: f32, center: Vec2, rotation: Rot) Polygon {
    return @bitCast(c.b2MakeOffsetBox(hx, hy, center, @bitCast(rotation)));
}

pub inline fn getByteCount() usize {
    return @intCast(c.b2GetByteCount());
}

pub inline fn setLengthUnitsPerMeter(units: f32) void {
    c.b2SetLengthUnitsPerMeter(units);
}

pub inline fn getLengthUnitsPerMeter() f32 {
    return c.b2GetLengthUnitsPerMeter();
}

pub inline fn getVersion() Version {
    return @bitCast(c.b2GetVersion());
}

pub inline fn setAllocator(allocFn: *alloc, freeFn: *free) void {
    c.b2SetAllocator(@ptrCast(&allocFn), @ptrCast(&freeFn));
}

pub inline fn setAssertFn(callback: *assert) void {
    c.b2SetAssertFcn(@ptrCast(callback));
}

pub inline fn unwindAngle(angle: f32) f32 {
    const pi = std.math.pi;
    const tau = std.math.tau;
    return if (angle < -pi)
        angle + tau
    else if (angle > pi)
        angle - tau
    else
        angle;
}

pub inline fn unwindLargeAngle(angle: f32) f32 {
    var realAngle = angle;
    while (realAngle > std.math.pi) realAngle -= 2.0 * std.path.pi;
    while (realAngle < -std.math.pi) realAngle += 2.0 * std.path.pi;
    return realAngle;
}

pub inline fn atan2(y: f32, x: f32) f32 {
    return c.b2Atan2(y, x);
}

pub inline fn segmentDistance(p1: Vec2, q1: Vec2, p2: Vec2, q2: Vec2) SegmentDistanceResult {
    return @bitCast(c.b2SegmentDistance(@bitCast(p1), @bitCast(q1), @bitCast(p2), @bitCast(q2)));
}

pub inline fn collideCircles(circle_a: Circle, transform_a: Transform, circle_b: Circle, transform_b: Transform) Manifold {
    return @bitCast(c.b2CollideCircles(@ptrCast(&circle_a), @bitCast(transform_a), @ptrCast(&circle_b), @bitCast(transform_b)));
}

pub inline fn collideCapsuleAndCircle(capsule_a: Capsule, transform_a: Transform, circle_b: Circle, transform_b: Transform) Manifold {
    return @bitCast(c.b2CollideCapsuleAndCircle(@ptrCast(&capsule_a), @bitCast(transform_a), @ptrCast(&circle_b), @bitCast(transform_b)));
}

pub inline fn collideSegmentAndCircle(segment_a: Segment, transform_a: Transform, circle_b: Circle, transform_b: Transform) Manifold {
    return @bitCast(c.b2CollideSegmentAndCircle(@ptrCast(&segment_a), @bitCast(transform_a), @ptrCast(&circle_b), @bitCast(transform_b)));
}

pub inline fn collidePolygonAndCircle(polygon_a: Polygon, transform_a: Transform, circle_b: Circle, transform_b: Transform) Manifold {
    return @bitCast(c.b2CollidePolygonAndCircle(@ptrCast(&polygon_a), @bitCast(transform_a), @ptrCast(&circle_b), @bitCast(transform_b)));
}

pub inline fn collideCapsules(capsule_a: Capsule, transform_a: Transform, capsule_b: Capsule, transform_b: Transform, cache: *DistanceCache) Manifold {
    return @bitCast(c.b2CollideCapsules(@ptrCast(&capsule_a), @bitCast(transform_a), @ptrCast(&capsule_b), @bitCast(transform_b), @ptrCast(cache)));
}

pub inline fn collideSegmentAndCapsule(segment_a: Segment, transform_a: Transform, capsule_b: Capsule, transform_b: Transform, cache: *DistanceCache) Manifold {
    return @bitCast(c.b2CollideSegmentAndCapsule(@ptrCast(&segment_a), @bitCast(transform_a), @ptrCast(&capsule_b), @bitCast(transform_b), @ptrCast(cache)));
}

pub inline fn collidePolygonAndCapsule(polygon_a: Polygon, transform_a: Transform, capsule_b: Capsule, transform_b: Transform, cache: *DistanceCache) Manifold {
    return @bitCast(c.b2CollidePolygonAndCapsule(@ptrCast(&polygon_a), @bitCast(transform_a), @ptrCast(&capsule_b), @bitCast(transform_b), @ptrCast(cache)));
}

pub inline fn collidePolygons(polygon_a: Polygon, transform_a: Transform, polygon_b: Polygon, transform_b: Transform, cache: *DistanceCache) Manifold {
    return @bitCast(c.b2CollidePolygons(@ptrCast(&polygon_a), @bitCast(transform_a), @ptrCast(&polygon_b), @bitCast(transform_b), @ptrCast(cache)));
}

pub inline fn collideSegmentAndPolygon(segment_a: Segment, transform_a: Transform, polygon_b: Polygon, transform_b: Transform, cache: *DistanceCache) Manifold {
    return @bitCast(c.b2CollideSegmentAndPolygon(@ptrCast(&segment_a), @bitCast(transform_a), @ptrCast(&polygon_b), @bitCast(transform_b), @ptrCast(cache)));
}

pub inline fn collideChainSegmentAndCircle(chain_segment_a: ChainSegment, transform_a: Transform, circle_b: Circle, transform_b: Transform) Manifold {
    return @bitCast(c.b2CollideChainSegmentAndCircle(@ptrCast(&chain_segment_a), @bitCast(transform_a), @ptrCast(&circle_b), @bitCast(transform_b)));
}

pub inline fn collideChainSegmentAndCapsule(chain_segment_a: ChainSegment, transform_a: Transform, capsule_b: Capsule, transform_b: Transform, cache: *DistanceCache) Manifold {
    return @bitCast(c.b2CollideChainSegmentAndCapsule(@ptrCast(&chain_segment_a), @bitCast(transform_a), @ptrCast(&capsule_b), @bitCast(transform_b), @ptrCast(cache)));
}

pub inline fn collideChainSegmentAndPolygon(chain_segment_a: ChainSegment, transform_a: Transform, polygon_b: Polygon, transform_b: Transform, cache: *DistanceCache) Manifold {
    return @bitCast(c.b2CollideChainSegmentAndPolygon(@ptrCast(&chain_segment_a), @bitCast(transform_a), @ptrCast(&polygon_b), @bitCast(transform_b), @ptrCast(cache)));
}
