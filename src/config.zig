const std = @import("std");

const config_types = @import("./config_types.zig");
const Tile = config_types.Tile;
const TileType = config_types.TileType;
const FillingPattern = config_types.FillingPattern;
const LayoutSpecification = config_types.LayoutSpecification;
const Command = config_types.command;

pub fn layout_specification(allocator: std.mem.Allocator, view_count: u32, usable_width: u32, usable_height: u32, tags: u32) !LayoutSpecification {
    _ = usable_width;
    _ = usable_height;
    _ = tags;

    // See config_types.zig for the definitions of the data types

    // The contents of tiles (which can be either subtiles or windows) are either horizontally
    // (hsplit) or vertically (vsplit) arranged. Whether a tile holds subtiles or windows is
    // determined by whether the .contents union has .subtiles or .filling (a "filling ID" which is
    // used to address the tile in the filling pattern) below.

    const root_tile = Tile{
        .typ = TileType.hsplit,

        .stretch = 1,

        .contents = .{
            .subtiles = try allocator.alloc(Tile, 3),
        },
    };
    root_tile.contents.subtiles[0] = Tile{
        .typ = .vsplit,
        .stretch = 25,
        .contents = .{
            .filling = 1,
        },
    };
    root_tile.contents.subtiles[1] = Tile{
        .typ = .vsplit,
        .stretch = if (view_count == 1) 70 else 50,
        .contents = .{
            .filling = 0,
        },
    };
    root_tile.contents.subtiles[2] = Tile{
        .typ = .vsplit,
        .stretch = 25,
        .contents = .{
            .filling = 2,
        },
    };

    // The filling pattern determines how windows are assigned to places in the grid. The .tiles
    // list is a list of tile IDs that are to be filled in a round-robin fashion.

    const filling_pattern = try allocator.alloc(FillingPattern, 2);

    filling_pattern[0] = FillingPattern{
        .tiles = try allocator.alloc(u32, 1),
        .max_views = 1,
    };
    filling_pattern[0].tiles[0] = 0;

    filling_pattern[1] = FillingPattern{
        .tiles = try allocator.alloc(u32, 2),
        .max_views = null, // All remaining views
    };
    filling_pattern[1].tiles[0] = 1;
    filling_pattern[1].tiles[1] = 2;

    return LayoutSpecification{
        // TODO refactor to be memory-holding object
        .tiles = root_tile,
        .filling_pattern = filling_pattern,
    };
}

//pub const commands = [_]Command{
//
//}
