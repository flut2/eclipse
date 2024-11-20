const std = @import("std");
const element = @import("../ui/elements/element.zig");
const shared = @import("shared");
const utils = shared.utils;
const game_data = shared.game_data;
const assets = @import("../assets.zig");
const particles = @import("particles.zig");
const map = @import("map.zig");
const main = @import("../main.zig");
const base = @import("object_base.zig");
const render = @import("../render.zig");
const px_per_tile = Camera.px_per_tile;

const Camera = @import("../Camera.zig");
const Purchasable = @This();

map_id: u32 = std.math.maxInt(u32),
data_id: u16 = std.math.maxInt(u16),
x: f32 = 0.0,
y: f32 = 0.0,
z: f32 = 0.0,
alpha: f32 = 1.0,
currency: game_data.Currency = .gold,
cost: u32 = 0,
cost_text_data: ?element.TextData = null,
name: ?[]const u8 = null,
name_text_data: ?element.TextData = null,
size_mult: f32 = 0,
atlas_data: assets.AtlasData = .default,
data: *const game_data.PurchasableData = undefined,

pub fn addToMap(purchasable_data: Purchasable) void {
    base.addToMap(purchasable_data, Purchasable);
}

pub fn deinit(self: *Purchasable) void {
    base.deinit(self);
}

pub fn draw(_: *Purchasable, _: render.CameraData, _: f32) void {}

pub fn update(_: *Purchasable, _: i64) void {}
