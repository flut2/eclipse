const glfw = @import("mach-glfw");
const settings = @import("settings.zig");
const std = @import("std");
const map = @import("game/map.zig");
const main = @import("main.zig");
const camera = @import("camera.zig");
const element = @import("ui/element.zig");
const assets = @import("assets.zig");
const network = @import("network.zig");
const game_data = @import("game_data.zig");
const ui_systems = @import("ui/systems.zig");
const GameScreen = @import("ui/screens/game_screen.zig").GameScreen;

var move_up: f32 = 0.0;
var move_down: f32 = 0.0;
var move_left: f32 = 0.0;
var move_right: f32 = 0.0;
var rotate_left: i8 = 0;
var rotate_right: i8 = 0;

pub var attacking: bool = false;
pub var walking_speed_multiplier: f32 = 1.0;
pub var rotate: i8 = 0;
pub var mouse_x: f32 = 0.0;
pub var mouse_y: f32 = 0.0;

pub var selected_key_mapper: ?*element.KeyMapper = null;
pub var selected_input_field: ?*element.Input = null;
pub var input_history: std.ArrayList([]const u8) = undefined;
pub var input_history_idx: u16 = 0;

pub var disable_input: bool = false;

pub fn reset() void {
    move_up = 0.0;
    move_down = 0.0;
    move_left = 0.0;
    move_right = 0.0;
    rotate_left = 0;
    rotate_right = 0;
    rotate = 0;
    attacking = false;
}

pub fn init(allocator: std.mem.Allocator) void {
    input_history = std.ArrayList([]const u8).init(allocator);
}

pub fn deinit(allocator: std.mem.Allocator) void {
    for (input_history.items) |msg| {
        allocator.free(msg);
    }
    input_history.deinit();
}

// todo isolate the ingame and editor logic

fn keyPress(window: glfw.Window, key: glfw.Key) void {
    if (ui_systems.screen != .game and ui_systems.screen != .editor)
        return;

    if (disable_input)
        return;

    if (key == settings.move_up.getKey()) {
        move_up = 1.0;
    } else if (key == settings.move_down.getKey()) {
        move_down = 1.0;
    } else if (key == settings.move_left.getKey()) {
        move_left = 1.0;
    } else if (key == settings.move_right.getKey()) {
        move_right = 1.0;
    } else if (key == settings.rotate_left.getKey()) {
        rotate_left = 1;
    } else if (key == settings.rotate_right.getKey()) {
        rotate_right = 1;
    } else if (key == settings.walk.getKey()) {
        walking_speed_multiplier = 0.5;
    } else if (key == settings.reset_camera.getKey()) {
        camera.angle = 0;
    } else if (key == settings.shoot.getKey()) {
        if (ui_systems.screen == .game) {
            attacking = true;
        }
    } else if (key == settings.ability_1.getKey()) {
        useAbility(0);
    } else if (key == settings.ability_2.getKey()) {
        useAbility(1);
    } else if (key == settings.ability_3.getKey()) {
        useAbility(2);
    } else if (key == settings.ultimate_ability.getKey()) {
        useAbility(3);
    } else if (key == settings.options.getKey()) {
        openOptions();
    } else if (key == settings.escape.getKey()) {
        tryEscape();
    } else if (key == settings.interact.getKey()) {
        const int_id = map.interactive_id.load(.Acquire);
        if (int_id != -1) {
            switch (map.interactive_type.load(.Acquire)) {
                .portal => main.server.queuePacket(.{ .use_portal = .{ .obj_id = int_id } }),
                else => {},
            }
        }
    } else if (key == settings.chat.getKey()) {
        selected_input_field = ui_systems.screen.game.chat_input;
        selected_input_field.?.last_input = 0;
    } else if (key == settings.chat_cmd.getKey()) {
        charEvent(window, @intFromEnum(glfw.Key.slash));
        selected_input_field = ui_systems.screen.game.chat_input;
        selected_input_field.?.last_input = 0;
    } else if (key == settings.toggle_perf_stats.getKey()) {
        settings.stats_enabled = !settings.stats_enabled;
    } else if (key == settings.toggle_stats.getKey()) {
        if (ui_systems.screen == .game) {
            GameScreen.statsCallback(ui_systems.screen.game);
        }
    }
}

fn keyRelease(key: glfw.Key) void {
    if (ui_systems.screen != .game and ui_systems.screen != .editor)
        return;

    if (disable_input)
        return;

    if (key == settings.move_up.getKey()) {
        move_up = 0.0;
    } else if (key == settings.move_down.getKey()) {
        move_down = 0.0;
    } else if (key == settings.move_left.getKey()) {
        move_left = 0.0;
    } else if (key == settings.move_right.getKey()) {
        move_right = 0.0;
    } else if (key == settings.rotate_left.getKey()) {
        rotate_left = 0;
    } else if (key == settings.rotate_right.getKey()) {
        rotate_right = 0;
    } else if (key == settings.walk.getKey()) {
        walking_speed_multiplier = 1.0;
    } else if (key == settings.shoot.getKey()) {
        if (ui_systems.screen == .game) {
            attacking = false;
        }
    }
}

fn mousePress(window: glfw.Window, button: glfw.MouseButton) void {
    if (ui_systems.screen != .game and ui_systems.screen != .editor)
        return;

    if (disable_input)
        return;

    if (button == settings.move_up.getMouse()) {
        move_up = 1.0;
    } else if (button == settings.move_down.getMouse()) {
        move_down = 1.0;
    } else if (button == settings.move_left.getMouse()) {
        move_left = 1.0;
    } else if (button == settings.move_right.getMouse()) {
        move_right = 1.0;
    } else if (button == settings.rotate_left.getMouse()) {
        rotate_left = 1;
    } else if (button == settings.rotate_right.getMouse()) {
        rotate_right = 1;
    } else if (button == settings.walk.getMouse()) {
        walking_speed_multiplier = 0.5;
    } else if (button == settings.reset_camera.getMouse()) {
        camera.angle = 0;
    } else if (button == settings.shoot.getMouse()) {
        if (ui_systems.screen == .game) {
            attacking = true;
        }
    } else if (button == settings.ability_1.getMouse()) {
        useAbility(0);
    } else if (button == settings.ability_2.getMouse()) {
        useAbility(1);
    } else if (button == settings.ability_3.getMouse()) {
        useAbility(2);
    } else if (button == settings.ultimate_ability.getMouse()) {
        useAbility(3);
    } else if (button == settings.options.getMouse()) {
        openOptions();
    } else if (button == settings.escape.getMouse()) {
        tryEscape();
    } else if (button == settings.interact.getMouse()) {
        const int_id = map.interactive_id.load(.Acquire);
        if (int_id != -1) {
            switch (map.interactive_type.load(.Acquire)) {
                .portal => main.server.queuePacket(.{ .use_portal = .{ .obj_id = int_id } }),
                else => {},
            }
        }
    } else if (button == settings.chat.getMouse()) {
        if (ui_systems.screen == .game) {
            selected_input_field = ui_systems.screen.game.chat_input;
            selected_input_field.?.last_input = 0;
        }
    } else if (button == settings.chat_cmd.getMouse()) {
        if (ui_systems.screen == .game) {
            charEvent(window, @intFromEnum(glfw.Key.slash));
            selected_input_field = ui_systems.screen.game.chat_input;
            selected_input_field.?.last_input = 0;
        }
    } else if (button == settings.toggle_perf_stats.getMouse()) {
        settings.stats_enabled = !settings.stats_enabled;
    } else if (button == settings.toggle_stats.getMouse()) {
        if (ui_systems.screen == .game) {
            GameScreen.statsCallback(ui_systems.screen.game);
        }
    }
}

fn mouseRelease(button: glfw.MouseButton) void {
    if (ui_systems.screen != .game and ui_systems.screen != .editor)
        return;

    if (disable_input)
        return;

    if (button == settings.move_up.getMouse()) {
        move_up = 0.0;
    } else if (button == settings.move_down.getMouse()) {
        move_down = 0.0;
    } else if (button == settings.move_left.getMouse()) {
        move_left = 0.0;
    } else if (button == settings.move_right.getMouse()) {
        move_right = 0.0;
    } else if (button == settings.rotate_left.getMouse()) {
        rotate_left = 0;
    } else if (button == settings.rotate_right.getMouse()) {
        rotate_right = 0;
    } else if (button == settings.walk.getMouse()) {
        walking_speed_multiplier = 1.0;
    } else if (button == settings.shoot.getMouse()) {
        if (ui_systems.screen == .game) {
            attacking = false;
        }
    }
}

fn useAbility(index: u8) void {
    map.object_lock.lock();
    defer map.object_lock.unlock();

    if (map.localPlayerRef()) |player| player.useAbility(index);
}

pub fn charEvent(_: glfw.Window, char: u21) void {
    if (selected_input_field) |input_field| {
        if (char > std.math.maxInt(u8) or char < std.math.minInt(u8)) {
            return;
        }

        const byte_code: u8 = @intCast(char);
        if (!std.ascii.isASCII(byte_code) or input_field.index >= 256)
            return;

        input_field.text_data.backing_buffer[input_field.index] = byte_code;
        input_field.index += 1;
        input_field.text_data.text = input_field.text_data.backing_buffer[0..input_field.index];
        input_field.inputUpdate();
        return;
    }
}

pub fn keyEvent(window: glfw.Window, key: glfw.Key, _: i32, action: glfw.Action, mods: glfw.Mods) void {
    if (action == .press or action == .repeat) {
        if (selected_key_mapper) |key_mapper| {
            key_mapper.mouse = .eight;
            key_mapper.key = key;
            key_mapper.listening = false;
            key_mapper.set_key_callback(key_mapper);
            selected_key_mapper = null;
        }

        if (selected_input_field) |input_field| {
            if (mods.control) {
                switch (key) {
                    .c => {
                        const old = input_field.text_data.text;
                        input_field.text_data.backing_buffer[input_field.index] = 0;
                        glfw.setClipboardString(input_field.text_data.backing_buffer[0..input_field.index :0]);
                        input_field.text_data.text = old;
                    },
                    .v => {
                        if (glfw.getClipboardString()) |clip_str| {
                            const clip_len = clip_str.len;
                            @memcpy(input_field.text_data.backing_buffer[input_field.index .. input_field.index + clip_len], clip_str);
                            input_field.index += @intCast(clip_len);
                            input_field.text_data.text = input_field.text_data.backing_buffer[0..input_field.index];
                            input_field.inputUpdate();
                            return;
                        }
                    },
                    .x => {
                        input_field.text_data.backing_buffer[input_field.index] = 0;
                        glfw.setClipboardString(input_field.text_data.backing_buffer[0..input_field.index :0]);
                        input_field.clear();
                        return;
                    },
                    else => {},
                }
            }

            switch (key) {
                .enter => {
                    if (input_field.enter_callback) |enter_cb| {
                        enter_cb(input_field.text_data.text);
                        input_field.clear();
                        input_field.last_input = -1;
                        selected_input_field = null;
                    }

                    return;
                },
                .backspace => {
                    if (input_field.index > 0) {
                        input_field.index -= 1;
                        input_field.text_data.text = input_field.text_data.backing_buffer[0..input_field.index];
                        input_field.inputUpdate();
                        return;
                    }
                },
                else => {},
            }

            if (input_field.is_chat) {
                if (key == .up) {
                    if (input_history_idx > 0) {
                        input_history_idx -= 1;
                        const msg = input_history.items[input_history_idx];
                        const msg_len = msg.len;
                        @memcpy(input_field.text_data.backing_buffer[0..msg_len], msg);
                        input_field.text_data.text = input_field.text_data.backing_buffer[0..msg_len];
                        input_field.index = @intCast(msg_len);
                        input_field.inputUpdate();
                    }

                    return;
                }

                if (key == .down) {
                    if (input_history_idx < input_history.items.len) {
                        input_history_idx += 1;

                        if (input_history_idx == input_history.items.len) {
                            input_field.clear();
                        } else {
                            const msg = input_history.items[input_history_idx];
                            const msg_len = msg.len;
                            @memcpy(input_field.text_data.backing_buffer[0..msg_len], msg);
                            input_field.text_data.text = input_field.text_data.backing_buffer[0..msg_len];
                            input_field.index = @intCast(msg_len);
                            input_field.inputUpdate();
                        }
                    }

                    return;
                }
            }

            return;
        }
    }

    if (action == .press) {
        keyPress(window, key);
        if (ui_systems.screen == .editor) {
            ui_systems.screen.editor.onKeyPress(key);
        }
    } else if (action == .release) {
        keyRelease(key);
        if (ui_systems.screen == .editor) {
            ui_systems.screen.editor.onKeyRelease(key);
        }
    }

    updateState();
}

pub fn mouseEvent(window: glfw.Window, button: glfw.MouseButton, action: glfw.Action, mods: glfw.Mods) void {
    if (action == .press) {
        window.setCursor(switch (settings.cursor_type) {
            .basic => assets.default_cursor_pressed,
            .royal => assets.royal_cursor_pressed,
            .ranger => assets.ranger_cursor_pressed,
            .aztec => assets.aztec_cursor_pressed,
            .fiery => assets.fiery_cursor_pressed,
            .target_enemy => assets.target_enemy_cursor_pressed,
            .target_ally => assets.target_ally_cursor_pressed,
        });
    } else if (action == .release) {
        window.setCursor(switch (settings.cursor_type) {
            .basic => assets.default_cursor,
            .royal => assets.royal_cursor,
            .ranger => assets.ranger_cursor,
            .aztec => assets.aztec_cursor,
            .fiery => assets.fiery_cursor,
            .target_enemy => assets.target_enemy_cursor,
            .target_ally => assets.target_ally_cursor,
        });
    }
    if (action == .press) {
        if (!ui_systems.mousePress(mouse_x, mouse_y, mods, button)) {
            mousePress(window, button);

            if (ui_systems.screen == .editor) {
                ui_systems.screen.editor.onMousePress(button);
            }
        }
    } else if (action == .release) {
        if (!ui_systems.mouseRelease(mouse_x, mouse_y)) {
            if (ui_systems.screen == .editor) {
                ui_systems.screen.editor.onMouseRelease(button);
            }
            mouseRelease(button);
        }
    }

    updateState();
}

pub fn updateState() void {
    rotate = rotate_right - rotate_left;

    // need a writer lock for shooting
    map.object_lock.lock();
    defer map.object_lock.unlock();

    if (map.localPlayerRef()) |local_player| {
        const y_dt = move_down - move_up;
        const x_dt = move_right - move_left;
        local_player.move_angle = if (y_dt == 0 and x_dt == 0) std.math.nan(f32) else std.math.atan2(y_dt, x_dt);
        local_player.walk_speed_multiplier = walking_speed_multiplier;

        if (attacking) {
            const shoot_angle = std.math.atan2(mouse_y - camera.screen_height / 2.0, mouse_x - camera.screen_width / 2.0) + camera.angle;
            local_player.weaponShoot(shoot_angle, main.current_time);
        }
    }
}

pub fn mouseMoveEvent(_: glfw.Window, x_pos: f64, y_pos: f64) void {
    mouse_x = @floatCast(x_pos);
    mouse_y = @floatCast(y_pos);

    _ = ui_systems.mouseMove(mouse_x, mouse_y);
}

pub fn scrollEvent(_: glfw.Window, x_offset: f64, y_offset: f64) void {
    if (!ui_systems.mouseScroll(mouse_x, mouse_y, @floatCast(x_offset), @floatCast(y_offset))) {
        switch (ui_systems.screen) {
            .game => {
                const size = @max(map.width, map.height);
                const max_zoom: f32 = @floatFromInt(@divFloor(size, 32));
                const scroll_speed = @as(f32, @floatFromInt(size)) / 1280;

                camera.minimap_zoom += @floatCast(y_offset * scroll_speed);
                camera.minimap_zoom = @max(1, @min(max_zoom, camera.minimap_zoom));
            },
            .editor => {
                const min_zoom = 0.05;
                const scroll_speed = 0.01;

                camera.scale += @floatCast(y_offset * scroll_speed);
                camera.scale = @min(1, @max(min_zoom, camera.scale));
            },
            else => {},
        }
    }
}

pub fn tryEscape() void {
    if (ui_systems.screen != .game or std.mem.eql(u8, map.name, "the Retrieve"))
        return;

    main.server.queuePacket(.{ .escape = .{} });
}

pub fn openOptions() void {
    if (ui_systems.screen == .game) {
        ui_systems.screen.game.options.setVisible(true);
        disable_input = true;
    }

    if (ui_systems.screen == .editor) {
        ui_systems.ui_lock.lock();
        defer ui_systems.ui_lock.unlock();
        ui_systems.switchScreen(.main_menu);
    }
}
