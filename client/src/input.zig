const std = @import("std");

const glfw = @import("zglfw");
const shared = @import("shared");
const game_data = shared.game_data;
const f32i = shared.utils.f32i;

const assets = @import("assets.zig");
const map = @import("game/map.zig");
const Player = @import("game/Player.zig");
const main = @import("main.zig");
const Input = @import("ui/elements/Input.zig");
const KeyMapper = @import("ui/elements/KeyMapper.zig");
const GameScreen = @import("ui/screens/GameScreen.zig");
const ui_systems = @import("ui/systems.zig");

const press_mappings = .{
    .{ &main.settings.move_up, handleMoveUpPress, true },
    .{ &main.settings.move_down, handleMoveDownPress, true },
    .{ &main.settings.move_left, handleMoveLeftPress, true },
    .{ &main.settings.move_right, handleMoveRightPress, true },
    .{ &main.settings.walk, handleWalkPress, true },
    .{ &main.settings.shoot, handleShootPress, false },
    .{ &main.settings.options, handleOptions, false },
    .{ &main.settings.escape, handleEscape, false },
    .{ &main.settings.interact, handleInteract, false },
    .{ &main.settings.chat, handleChat, false },
    .{ &main.settings.chat_cmd, handleChatCmd, false },
    .{ &main.settings.toggle_perf_stats, handleTogglePerfStats, true },
    .{ &main.settings.ability_1, handleAbility1, false },
    .{ &main.settings.ability_2, handleAbility2, false },
    .{ &main.settings.ability_3, handleAbility3, false },
    .{ &main.settings.ability_4, handleAbility4, false },
};

const release_mappings = .{
    .{ &main.settings.move_up, handleMoveUpRelease, true },
    .{ &main.settings.move_down, handleMoveDownRelease, true },
    .{ &main.settings.move_left, handleMoveLeftRelease, true },
    .{ &main.settings.move_right, handleMoveRightRelease, true },
    .{ &main.settings.walk, handleWalkRelease, true },
    .{ &main.settings.shoot, handleShootRelease, false },
};

var move_up: f32 = 0.0;
var move_down: f32 = 0.0;
var move_left: f32 = 0.0;
var move_right: f32 = 0.0;

pub var attacking: bool = false;
pub var walking_speed_multiplier: f32 = 1.0;
pub var move_angle: f32 = std.math.nan(f32);
pub var mouse_x: f32 = 0.0;
pub var mouse_y: f32 = 0.0;

pub var selected_key_mapper: ?*KeyMapper = null;
pub var selected_input_field: ?*Input = null;
pub var input_history: std.ArrayListUnmanaged([]const u8) = .empty;
pub var input_history_idx: u16 = 0;

pub var disable_input: bool = false;

pub fn reset() void {
    move_up = 0.0;
    move_down = 0.0;
    move_left = 0.0;
    move_right = 0.0;
    attacking = false;
}

pub fn deinit() void {
    for (input_history.items) |msg| main.allocator.free(msg);
    input_history.deinit(main.allocator);
}

fn handleMoveUpPress() void {
    move_up = 1.0;
}

fn handleMoveDownPress() void {
    move_down = 1.0;
}

fn handleMoveLeftPress() void {
    move_left = 1.0;
}

fn handleMoveRightPress() void {
    move_right = 1.0;
}

fn handleWalkPress() void {
    walking_speed_multiplier = 0.5;
}

fn handleShootPress() void {
    if (ui_systems.screen == .game) attacking = true;
}

fn handleMoveUpRelease() void {
    move_up = 0.0;
}

fn handleMoveDownRelease() void {
    move_down = 0.0;
}

fn handleMoveLeftRelease() void {
    move_left = 0.0;
}

fn handleMoveRightRelease() void {
    move_right = 0.0;
}

fn handleWalkRelease() void {
    walking_speed_multiplier = 1.0;
}

fn handleShootRelease() void {
    if (ui_systems.screen == .game) attacking = false;
}

pub fn handleOptions() void {
    if (ui_systems.screen == .game) {
        ui_systems.screen.game.options.setVisible(true);
        disable_input = true;
    }
}

fn handleEscape() void {
    if (ui_systems.screen == .game) main.game_server.sendPacket(.{ .escape = .{} });
}

fn handleInteract() void {
    const int_id = map.interactive.map_id.load(.acquire);
    if (int_id != -1) {
        switch (map.interactive.type.load(.acquire)) {
            .portal => main.game_server.sendPacket(.{ .use_portal = .{ .portal_map_id = int_id } }),
            else => {},
        }
    }
}

fn handleChat() void {
    selected_input_field = ui_systems.screen.game.chat_input;
    selected_input_field.?.last_input = 0;
}

fn handleChatCmd() void {
    charEvent(main.window, @intFromEnum(glfw.Key.slash));
    selected_input_field = ui_systems.screen.game.chat_input;
    selected_input_field.?.last_input = 0;
}

fn handleTogglePerfStats() void {
    main.settings.stats_enabled = !main.settings.stats_enabled;
}

fn handleAbility1() void {
    map.object_lock.lock();
    defer map.object_lock.unlock();
    if (map.localPlayer(.ref)) |player| player.useAbility(0);
}

fn handleAbility2() void {
    map.object_lock.lock();
    defer map.object_lock.unlock();
    if (map.localPlayer(.ref)) |player| player.useAbility(1);
}

fn handleAbility3() void {
    map.object_lock.lock();
    defer map.object_lock.unlock();
    if (map.localPlayer(.ref)) |player| player.useAbility(2);
}

fn handleAbility4() void {
    map.object_lock.lock();
    defer map.object_lock.unlock();
    if (map.localPlayer(.ref)) |player| player.useAbility(3);
}

pub fn charEvent(_: *glfw.Window, char: u32) callconv(.C) void {
    if (selected_input_field) |input_field| {
        if (char > std.math.maxInt(u8) or char < std.math.minInt(u8)) return;

        const byte_code: u8 = @intCast(char);
        if (!std.ascii.isASCII(byte_code) or input_field.index >= 256) return;

        input_field.text_data.backing_buffer[input_field.index] = byte_code;
        input_field.index += 1;
        input_field.text_data.text = input_field.text_data.backing_buffer[0..input_field.index];
        input_field.inputUpdate();
        return;
    }
}

pub fn keyEvent(window: *glfw.Window, key: glfw.Key, _: i32, action: glfw.Action, mods: glfw.Mods) callconv(.C) void {
    if (action == .press or action == .repeat) {
        if (selected_key_mapper) |key_mapper| {
            key_mapper.settings_button.* = if (key == .escape) .{ .key = .unknown } else .{ .key = key };
            key_mapper.listening = false;
            key_mapper.setKeyCallback(key_mapper);
            selected_key_mapper = null;
        }

        if (selected_input_field) |input_field| {
            if (mods.control) {
                switch (key) {
                    .c => {
                        const old = input_field.text_data.text;
                        input_field.text_data.backing_buffer[input_field.index] = 0;
                        window.setClipboardString(input_field.text_data.backing_buffer[0..input_field.index :0]);
                        input_field.text_data.text = old;
                    },
                    .v => {
                        if (window.getClipboardString()) |clip_str| {
                            if (clip_str.len > 256 - input_field.index) return;
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
                        window.setClipboardString(input_field.text_data.backing_buffer[0..input_field.index :0]);
                        input_field.clear();
                        return;
                    },
                    else => {},
                }
            }

            switch (key) {
                .enter => {
                    if (input_field.enterCallback) |enterCb| {
                        enterCb(input_field.text_data.text);
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

        const is_editor = ui_systems.screen == .editor;
        if ((ui_systems.screen == .game or is_editor) and !disable_input)
            inline for (press_mappings) |mapping|
                if ((mapping[2] or !is_editor) and mapping[0].* == .key and mapping[0].key == key) mapping[1]();
        if (is_editor) ui_systems.screen.editor.onKeyPress(key);
    } else if (action == .release) {
        const is_editor = ui_systems.screen == .editor;
        if ((ui_systems.screen == .game or is_editor) and !disable_input)
            inline for (release_mappings) |mapping|
                if ((mapping[2] or !is_editor) and mapping[0].* == .key and mapping[0].key == key) mapping[1]();
        if (is_editor) ui_systems.screen.editor.onKeyRelease(key);
    }

    updateMove();
}

pub fn mouseEvent(window: *glfw.Window, button: glfw.MouseButton, action: glfw.Action, mods: glfw.Mods) callconv(.C) void {
    if (action == .press) {
        window.setCursor(switch (main.settings.cursor_type) {
            .basic => assets.default_cursor_pressed,
            .royal => assets.royal_cursor_pressed,
            .ranger => assets.ranger_cursor_pressed,
            .aztec => assets.aztec_cursor_pressed,
            .fiery => assets.fiery_cursor_pressed,
            .target_enemy => assets.target_enemy_cursor_pressed,
            .target_ally => assets.target_ally_cursor_pressed,
        });

        if (selected_input_field) |input_field| {
            input_field.last_input = -1;
            selected_input_field = null;
        }

        if (selected_key_mapper) |key_mapper| {
            key_mapper.settings_button.* = .{ .mouse = button };
            key_mapper.listening = false;
            key_mapper.setKeyCallback(key_mapper);
            selected_key_mapper = null;
        }

        if (!ui_systems.mousePress(mouse_x, mouse_y, mods)) {
            const is_editor = ui_systems.screen == .editor;
            if ((ui_systems.screen == .game or is_editor) and !disable_input)
                inline for (press_mappings) |mapping| if (mapping[0].* == .mouse and mapping[0].mouse == button) mapping[1]();
            if (is_editor) ui_systems.screen.editor.onMousePress(button);
        }
    } else if (action == .release) {
        window.setCursor(switch (main.settings.cursor_type) {
            .basic => assets.default_cursor,
            .royal => assets.royal_cursor,
            .ranger => assets.ranger_cursor,
            .aztec => assets.aztec_cursor,
            .fiery => assets.fiery_cursor,
            .target_enemy => assets.target_enemy_cursor,
            .target_ally => assets.target_ally_cursor,
        });
        if (!ui_systems.mouseRelease(mouse_x, mouse_y)) {
            const is_editor = ui_systems.screen == .editor;
            if ((ui_systems.screen == .game or is_editor) and !disable_input)
                inline for (release_mappings) |mapping| if (mapping[0].* == .mouse and mapping[0].mouse == button) mapping[1]();
            if (is_editor) ui_systems.screen.editor.onMouseRelease(button);
        }
    }

    updateMove();
}

pub fn updateMove() void {
    const y_dt = move_down - move_up;
    const x_dt = move_right - move_left;
    move_angle = if (y_dt == 0 and x_dt == 0) std.math.nan(f32) else std.math.atan2(y_dt, x_dt);
}

pub fn mouseMoveEvent(_: *glfw.Window, x_pos: f64, y_pos: f64) callconv(.C) void {
    mouse_x = @floatCast(x_pos);
    mouse_y = @floatCast(y_pos);

    _ = ui_systems.mouseMove(mouse_x, mouse_y);
}

pub fn scrollEvent(_: *glfw.Window, x_offset: f64, y_offset: f64) callconv(.C) void {
    if (!ui_systems.mouseScroll(mouse_x, mouse_y, @floatCast(x_offset), @floatCast(y_offset))) {
        switch (ui_systems.screen) {
            .game => {
                const size = @max(map.info.width, map.info.height);
                const max_zoom = f32i(@divFloor(size, 32));
                const scroll_speed = f32i(size) / 1280;

                main.camera.lock.lock();
                defer main.camera.lock.unlock();
                main.camera.minimap_zoom += @floatCast(y_offset * scroll_speed);
                main.camera.minimap_zoom = @max(1, @min(max_zoom, main.camera.minimap_zoom));
            },
            .editor => {
                const min_zoom = 0.05;
                const scroll_speed = 0.01;

                main.camera.lock.lock();
                defer main.camera.lock.unlock();
                main.camera.scale += @floatCast(y_offset * scroll_speed);
                main.camera.scale = @min(1, @max(min_zoom, main.camera.scale));
            },
            else => {},
        }
    }
}
