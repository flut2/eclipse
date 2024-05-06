const std = @import("std");
const game_data = @import("shared").game_data;

pub const Tile = struct {
    occupied: bool = false,
    x: u16 = 0,
    y: u16 = 0,
    tile_type: u16 = 0xFFFF,
    update_count: u16 = 0,
    props: *const game_data.GroundProps = undefined,
};
