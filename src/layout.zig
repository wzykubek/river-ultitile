const std = @import("std");

const config_types = @import("./config_types.zig");
const config = @import("./config.zig");

const FillingPattern = config_types.FillingPattern;
const Tile = config_types.Tile;

pub const Dimensions = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
};

fn highest_tile_filling_id(filling_pattern: []FillingPattern) u32 {
    var result: u32 = 0;
    for (filling_pattern) |pattern| {
        for (pattern.tiles) |tile_id| {
            if (tile_id > result) {
                result = tile_id;
            }
        }
    }
    return result;
}

fn determine_view_subtile_dimensions(tile: *const Tile, parent_dimensions: *const Dimensions, out_tiles: []*const Tile, out_dimensions: []Dimensions) void {
    switch (tile.contents) {
        .subtiles => |subtiles| {
            var stretch_total: u32 = 0;
            for (subtiles) |*subtile| stretch_total += subtile.stretch;

            var stretch_before: u32 = 0;
            for (subtiles) |*subtile| {
                const parent_before = switch (tile.typ) {
                    .hsplit => parent_dimensions.x,
                    .vsplit => parent_dimensions.y,
                };
                const parent_size: f32 = @floatFromInt(switch (tile.typ) {
                    .hsplit => parent_dimensions.width,
                    .vsplit => parent_dimensions.height,
                });

                const before: i32 = parent_before + @as(i32, @intFromFloat(@as(f32, @floatFromInt(stretch_before)) / @as(f32, @floatFromInt(stretch_total)) * parent_size));
                const size: u32 = @intFromFloat(@as(f32, @floatFromInt(subtile.stretch)) / @as(f32, @floatFromInt(stretch_total)) * parent_size);

                const dim = switch (tile.typ) {
                    .hsplit => Dimensions{
                        .x = before,
                        .y = parent_dimensions.y,
                        .width = size,
                        .height = parent_dimensions.height,
                    },
                    .vsplit => Dimensions{
                        .x = parent_dimensions.x,
                        .y = before,
                        .width = parent_dimensions.width,
                        .height = size,
                    },
                };
                determine_view_subtile_dimensions(subtile, &dim, out_tiles, out_dimensions);

                stretch_before += subtile.stretch;
            }
        },

        .filling => |filling_id| {
            out_tiles[filling_id] = tile;
            out_dimensions[filling_id] = parent_dimensions.*;
        },
    }
}

fn determine_amount_views_per_tile(allocator: std.mem.Allocator, view_count: u32, filling_pattern: []FillingPattern) ![]u32 {
    var view_tiles = try allocator.alloc(u32, highest_tile_filling_id(filling_pattern) + 1);
    for (view_tiles) |*view_tile| {
        view_tile.* = 0;
    }

    var views_left_to_assign = view_count;
    for (filling_pattern) |f| {
        var views_left_to_assign_in_this_pattern = @min(views_left_to_assign, f.max_views orelse std.math.maxInt(u32));

        while (views_left_to_assign_in_this_pattern > 0) {
            for (f.tiles) |tile_id| {
                view_tiles[tile_id] += 1;
                views_left_to_assign -= 1;
                views_left_to_assign_in_this_pattern -= 1;
                if (views_left_to_assign_in_this_pattern <= 0) break;
            }
        }
    }

    return view_tiles;
}

fn determine_view_dimensions(allocator: std.mem.Allocator, view_count: u32, filling_pattern: []FillingPattern, view_tiles: []*const Tile, view_tile_dimensions: []Dimensions) ![]Dimensions {
    const views_per_view_tile = try determine_amount_views_per_tile(allocator, view_count, filling_pattern);
    defer allocator.free(views_per_view_tile);

    var view_dimensions = try allocator.alloc(Dimensions, view_count);
    errdefer allocator.free(view_dimensions);

    var views_allocated_per_view_tile = try allocator.alloc(u32, views_per_view_tile.len);
    defer allocator.free(views_allocated_per_view_tile);
    for (views_allocated_per_view_tile) |*views_allocated| {
        views_allocated.* = 0;
    }

    var i: u32 = 0;
    var views_left_to_assign = view_count;
    for (filling_pattern) |f| {
        var views_left_to_assign_in_this_pattern = @min(views_left_to_assign, f.max_views orelse std.math.maxInt(u32));
        while (views_left_to_assign_in_this_pattern > 0) {
            for (f.tiles) |tile_id| {
                const parent_dimensions = view_tile_dimensions[tile_id];

                const parent_before = switch (view_tiles[tile_id].typ) {
                    .hsplit => parent_dimensions.x,
                    .vsplit => parent_dimensions.y,
                };
                const parent_size: f32 = @floatFromInt(switch (view_tiles[tile_id].typ) {
                    .hsplit => parent_dimensions.width,
                    .vsplit => parent_dimensions.height,
                });

                const before: i32 = parent_before + @as(i32, @intFromFloat(@as(f32, @floatFromInt(views_allocated_per_view_tile[tile_id])) / @as(f32, @floatFromInt(views_per_view_tile[tile_id])) * parent_size));
                const size: u32 = @intFromFloat(parent_size / @as(f32, @floatFromInt(views_per_view_tile[tile_id])));

                view_dimensions[i] = switch (view_tiles[tile_id].typ) {
                    .hsplit => Dimensions{
                        .x = before,
                        .y = parent_dimensions.y,
                        .width = size,
                        .height = parent_dimensions.height,
                    },
                    .vsplit => Dimensions{
                        .x = parent_dimensions.x,
                        .y = before,
                        .width = parent_dimensions.width,
                        .height = size,
                    },
                };

                i += 1;
                views_allocated_per_view_tile[tile_id] += 1;
                views_left_to_assign -= 1;
                views_left_to_assign_in_this_pattern -= 1;
                if (views_left_to_assign_in_this_pattern <= 0) break;
            }
        }
    }

    return view_dimensions;
}

pub fn layout(allocator: std.mem.Allocator, view_count: u32, usable_width: u31, usable_height: u31, tags: u32) ![]Dimensions {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const layout_specification = try config.layout_specification(arena_allocator, view_count, usable_width, usable_height, tags);
    const root_tile = &layout_specification.tiles;
    const filling_pattern = layout_specification.filling_pattern;

    const root_dimensions = Dimensions{
        .x = 0,
        .y = 0,
        .width = usable_width,
        .height = usable_height,
    };
    var view_tiles = try allocator.alloc(*const Tile, highest_tile_filling_id(filling_pattern) + 1);
    defer allocator.free(view_tiles);
    var view_tile_dimensions = try allocator.alloc(Dimensions, view_tiles.len);
    defer allocator.free(view_tile_dimensions);
    determine_view_subtile_dimensions(root_tile, &root_dimensions, view_tiles, view_tile_dimensions);

    return determine_view_dimensions(allocator, view_count, filling_pattern, view_tiles, view_tile_dimensions);
}
