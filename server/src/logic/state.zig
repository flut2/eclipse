const std = @import("std");
const game_data = @import("shared").game_data;
const xml = @import("shared").xml;
const behavior = @import("behavior.zig");
const transition = @import("transition.zig");

const Enemy = @import("../map/enemy.zig").Enemy;
const Behavior = behavior.Behavior;
const TempTransition = transition.TempTransition;
const Transition = transition.Transition;

pub const State = struct {
    name: ?[]const u8, // Only the root state name should be null
    states: []State,
    child_states: []State,
    child_behaviors: []Behavior,
    child_transitions: []Transition,

    pub fn entry(self: State, host: *Enemy, time: i64) !void {
        for (self.child_behaviors) |*b| {
            try b.entry(host, time);
        }
    }

    pub fn exit(self: State, host: *Enemy, time: i64) !void {
        for (self.child_behaviors) |*b| {
            try b.exit(host, time);
        }
    }

    pub fn tick(self: State, host: *Enemy, time: i64, dt: i64) !void {
        for (self.child_transitions) |*t| {
            if (try t.tick(host, time, dt)) {
                try host.active_state.?.exit(host, time);
                host.active_state = t.target_state;
                try host.active_state.?.entry(host, time);
                try host.active_state.?.tick(host, time, dt);
                return;
            }
        }

        for (self.child_behaviors) |*b| {
            try b.tick(host, time, dt);
        }
    }

    pub fn parse(node: xml.Node, allocator: std.mem.Allocator, parent_states: *std.ArrayList(State), comptime is_root: bool) !State {
        var ret: State = undefined;
        ret.name = if (is_root) null else try node.getAttributeAlloc("id", allocator, "");

        var states = std.ArrayList(State).init(allocator);
        defer states.deinit();

        var behaviors = std.ArrayList(Behavior).init(allocator);
        defer behaviors.deinit();

        var it = node.iterate(&.{}, "State");
        while (it.next()) |s_node| {
            try states.append(try State.parse(s_node, allocator, parent_states, false));
        }

        var next_node: ?*xml.c.xmlNode = @ptrCast(node.impl.children);
        while (next_node != null) : (next_node = next_node.?.next) {
            if (next_node.?.type != 1)
                continue;

            const name = std.mem.span(next_node.?.name orelse continue);
            const wrapped_node = xml.Node{ .impl = next_node.? };
            const eql = std.mem.eql;
            inline for (@typeInfo(behavior).Struct.decls) |decl| {
                comptime if (eql(u8, decl.name, "Behavior") or
                    eql(u8, decl.name, "BehaviorTag") or
                    eql(u8, decl.name, "BehaviorStorage"))
                    continue;

                if (eql(u8, decl.name, name)) {
                    try behaviors.append(try @field(behavior, decl.name).parse(wrapped_node, allocator));
                }
            }
        }

        ret.child_states = try allocator.dupe(State, states.items);
        ret.child_behaviors = try allocator.dupe(Behavior, behaviors.items);
        try parent_states.appendSlice(ret.child_states);

        if (is_root) {
            ret.populateStates(try allocator.dupe(State, parent_states.items));
            try ret.parseTransitions(node, allocator);
        }

        return ret;
    }

    pub fn populateStates(self: *State, states: []State) void {
        self.states = states;
        for (self.child_states) |*s| {
            s.populateStates(states);
        }
    }

    pub fn parseTransitions(self: *State, node: xml.Node, allocator: std.mem.Allocator) !void {
        var temp_transitions = std.ArrayList(TempTransition).init(allocator);
        defer temp_transitions.deinit();

        var next_node: ?*xml.c.xmlNode = @ptrCast(node.impl.children);
        while (next_node != null) : (next_node = next_node.?.next) {
            if (next_node.?.type != 1)
                continue;

            const name = std.mem.span(next_node.?.name orelse continue);
            const wrapped_node = xml.Node{ .impl = next_node.? };
            const eql = std.mem.eql;
            inline for (@typeInfo(transition).Struct.decls) |decl| {
                comptime if (eql(u8, decl.name, "TempTransition") or
                    eql(u8, decl.name, "Transition") or
                    eql(u8, decl.name, "TransitionTag") or
                    eql(u8, decl.name, "TransitionStorage") or
                    eql(u8, decl.name, "TransitionLogic"))
                    continue;

                if (eql(u8, decl.name, name)) {
                    try temp_transitions.append(try TempTransition.parse(wrapped_node, allocator, @field(transition, decl.name)));
                }
            }
        }

        const transitions = try allocator.alloc(Transition, temp_transitions.items.len);
        loop: for (transitions, temp_transitions.items) |*trans, temp_trans| {
            trans.logic = temp_trans.logic;

            for (self.states) |s| {
                if (s.name != null and std.mem.eql(u8, s.name.?, temp_trans.target_state)) {
                    trans.target_state = &s;
                    continue :loop;
                }
            }

            std.debug.panic("Target state (\"{s}\") not found while attempting to transition from state \"{s}\"", .{
                temp_trans.target_state,
                self.name orelse "$root",
            });
        }
        self.child_transitions = transitions;

        var it = node.iterate(&.{}, "State");
        while (it.next()) |s_node| {
            for (self.child_states) |*s| {
                if (std.mem.eql(u8, s.name.?, s_node.getAttribute("id") orelse continue))
                    try parseTransitions(s, s_node, allocator);
            }
        }
    }

    pub fn deinit(self: State, allocator: std.mem.Allocator) void {
        if (self.name) |name| {
            allocator.free(name);
        } else {
            for (self.states) |state| {
                state.deinit(allocator);
            }
            allocator.free(self.states);
        }

        for (self.child_behaviors) |behav| {
            behav.deinit(allocator);
        }
        allocator.free(self.child_behaviors);

        for (self.child_transitions) |trans| {
            trans.deinit(allocator);
        }
        allocator.free(self.child_transitions);
    }
};

pub var en_type_to_root_state: std.AutoHashMap(u16, State) = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    en_type_to_root_state = std.AutoHashMap(u16, State).init(allocator);

    const xmls_dir = try std.fs.cwd().openDir("./assets/logic", .{ .iterate = true });
    var walker = try xmls_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (std.mem.endsWith(u8, entry.path, ".xml")) {
            const path = std.fmt.allocPrintZ(allocator, "./assets/logic/{s}", .{entry.path}) catch continue;
            defer allocator.free(path);

            const doc = try xml.Doc.fromFile(path);
            defer doc.deinit();

            const root_node = doc.getRootElement() catch {
                std.log.err("Invalid XML in path {s}", .{path});
                continue;
            };
            if (!std.mem.eql(u8, std.mem.span(root_node.impl.name), "Behaviors")) {
                std.log.err("Non-behavior XML in path {s}", .{path});
                continue;
            }

            var it = root_node.iterate(&.{}, "Behavior");
            while (it.next()) |node| {
                const id = node.getAttribute("id") orelse "";
                const obj_type = game_data.obj_name_to_type.get(id) orelse {
                    std.log.err("'{s}' not found while parsing behaviors (path: {s})", .{ id, path });
                    continue;
                };
                var all_states = std.ArrayList(State).init(allocator);
                defer all_states.deinit();

                try en_type_to_root_state.put(obj_type, try State.parse(node, allocator, &all_states, true));
            }
        }
    }
}

pub fn deinit(allocator: std.mem.Allocator) void {
    var it = en_type_to_root_state.valueIterator();
    while (it.next()) |state| {
        state.deinit(allocator);
    }
    en_type_to_root_state.deinit();
}
