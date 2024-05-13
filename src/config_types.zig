const std = @import("std");

pub const TileType = enum {
    hsplit,
    vsplit,
};

pub const ContentsTag = enum {
    subtiles,
    filling,
};

pub const Tile = struct {
    typ: TileType,

    /// Size (ratio; relative to the sizes of the other subtiles in the tile; ignored for the root
    /// tile)
    stretch: u32,
    // /// Maximum size (px) (0 for no maximum)
    // max_size: u32,
    // /// Minimum size (px)
    // min_size: u32,

    contents: union(ContentsTag) {
        subtiles: []Tile,
        filling: u32,
    },
    // /// Padding between contents (px)
    // padding: u32,
};

pub const FillingPattern = struct {
    /// IDs of tiles to fill in round-robin fashion. May be just one name for a simple filling
    /// pattern
    tiles: []u32,
    /// If null, all remaining views will be caught
    max_views: ?u32,
};

pub const LayoutSpecification = struct {
    tiles: Tile,
    filling_pattern: []FillingPattern,
};

//pub const Command = struct {
//    command: []u8,
//    args: [][]u8,
//    *const fn (tiles: *Tile, filling_pattern: []FillingPattern, args: [][]u8, tags: u32) void,
//};
