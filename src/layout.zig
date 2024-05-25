const std = @import("std");

const util = @import("./util.zig");
const config = @import("./config.zig");
const Tile = config.Tile;

// Tiling works as follows:
// first, views are assigned to buckets according to tile order (lowest first), with each bucket
// having the capacity of the sum of the associated tiles' capacities;
// within each bucket, tiles are attempted to be distributed evenly, with lower suborders getting
// earlier views

/// The stretch value used for views
pub const VIEW_STRETCH: u32 = 100;

pub const Dimensions = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
};

// TODO Maybe cleaner if separate data structure for dimensions and views_dimensions to avoid optional
const TileInfo = struct {
    allocator: std.mem.Allocator,
    tile: *const Tile,
    subtiles: []*TileInfo,
    parent_tile: ?*TileInfo,
    views: u32,
    views_recursive: u32,
    dimensions: ?Dimensions,
    views_dimensions: ?[]Dimensions,

    pub fn deinit(self: *TileInfo) void {
        self.allocator.free(self.subtiles);
        if (self.views_dimensions) |views_dimensions| self.allocator.free(views_dimensions);
    }
};

const TileInfos = struct {
    allocator: std.mem.Allocator,

    tile_infos: []TileInfo,
    order_suborder_map: [][]?*TileInfo,

    /// Takes ownership of the slices, which must have been allocated with `allocator`.
    pub fn initFromOwnedSlices(allocator: std.mem.Allocator, order_suborder_map: [][]?*TileInfo, tile_infos: []TileInfo) TileInfos {
        return .{
            .allocator = allocator,
            .tile_infos = tile_infos,
            .order_suborder_map = order_suborder_map,
        };
    }

    pub fn deinit(self: *TileInfos) void {
        for (self.tile_infos) |*tile_info| tile_info.deinit();
        for (self.order_suborder_map) |suborder_map| {
            self.allocator.free(suborder_map);
        }
        self.allocator.free(self.order_suborder_map);
        self.allocator.free(self.tile_infos);
    }
};

/// Find the highest "order" field a tile and its decendents have
fn highestOrder(tile: *const Tile) u32 {
    var result: u32 = if (tile.max_views != 0) tile.order else 0;
    for (tile.subtiles.items) |*subtile| {
        const subtile_highest = highestOrder(subtile);
        if (subtile_highest > result) result = subtile_highest;
    }
    return result;
}

/// Find the highest "suborder" field a tile and its decendents have
fn highestSuborder(tile: *const Tile) u32 {
    var result: u32 = if (tile.max_views != 0) tile.suborder else 0;
    for (tile.subtiles.items) |*subtile| {
        const subtile_highest = highestSuborder(subtile);
        if (subtile_highest > result) result = subtile_highest;
    }
    return result;
}

fn buildFillingInfoInner(allocator: std.mem.Allocator, tile: *const Tile, parent_tile_info: ?*TileInfo, out_order_suborder_map: [][]?*TileInfo, out_tile_infos: *std.ArrayList(TileInfo)) !*TileInfo {
    var tile_info = try out_tile_infos.addOne();
    tile_info.* = TileInfo{
        .allocator = allocator,
        .tile = tile,
        .subtiles = try allocator.alloc(*TileInfo, tile.subtiles.items.len),
        .parent_tile = parent_tile_info,
        .views = 0,
        .views_recursive = 0,
        .dimensions = null,
        .views_dimensions = null,
    };

    if (tile.max_views != 0) {
        out_order_suborder_map[tile.order][tile.suborder] = tile_info;
    }

    for (tile.subtiles.items, 0..) |*subtile, i| {
        tile_info.subtiles[i] = try buildFillingInfoInner(allocator, subtile, tile_info, out_order_suborder_map, out_tile_infos);
    }

    return tile_info;
}

fn buildFillingInfo(allocator: std.mem.Allocator, tile: *const Tile) !TileInfos {
    var order_suborder_map = try allocator.alloc([]?*TileInfo, highestOrder(tile) + 1);
    const highest_suborder = highestSuborder(tile);
    for (order_suborder_map) |*suborder_map| {
        suborder_map.* = try allocator.alloc(?*TileInfo, highest_suborder + 1);
        for (suborder_map.*) |*tile_info_opt| {
            tile_info_opt.* = null;
        }
    }
    errdefer {
        for (order_suborder_map) |suborder_map| allocator.free(suborder_map);
        allocator.free(order_suborder_map);
    }

    var tile_infos = std.ArrayList(TileInfo).init(allocator);
    errdefer tile_infos.deinit();
    _ = try buildFillingInfoInner(allocator, tile, null, order_suborder_map, &tile_infos);

    return TileInfos.initFromOwnedSlices(allocator, order_suborder_map, try tile_infos.toOwnedSlice());
}

fn createTestLayout(allocator: std.mem.Allocator) !Tile {
    var tile = try Tile.init(allocator, "test-layout");
    errdefer tile.deinit();
    tile.order = 1;
    tile.max_views = 1;

    var tile_left = try tile.addSubtile("left");
    var tile_left_sub = try tile_left.addSubtile("left-sub");
    tile_left_sub.order = 2;
    tile_left_sub.max_views = null;

    var tile_middle = try tile.addSubtile("middle");
    tile_middle.order = 2;
    tile_middle.suborder = 1;
    tile_middle.max_views = null;

    var tile_right = try tile.addSubtile("right");
    var tile_right_sub = try tile_right.addSubtile("right-sub");
    tile_right_sub.order = 1;
    // max_views is 0 so this tile should end up in the non-fillable tile list

    var tile_right_sub_sub = try tile_right_sub.addSubtile("sub2");
    tile_right_sub_sub.order = 1;
    tile_right_sub_sub.suborder = 1;
    tile_right_sub_sub.max_views = 2;

    return tile;
}

test {
    var tile = try createTestLayout(std.testing.allocator);
    defer tile.deinit();

    var tile_infos = try buildFillingInfo(std.testing.allocator, &tile);
    defer tile_infos.deinit();

    const expected_order_map = [3][2]?[]const u8{
        // order 0
        .{
            null,
            null,
        },
        // order 1
        .{
            "test-layout",
            "sub2",
        },
        // order 2
        .{
            "left-sub",
            "middle",
        },
    };
    for (expected_order_map, tile_infos.order_suborder_map) |expected_suborder_map, actual_suborder_map| {
        for (expected_suborder_map, actual_suborder_map) |expected_opt, actual| {
            if (expected_opt) |expected_name| {
                try std.testing.expectEqualStrings(expected_name, actual.?.tile.name);
            } else {
                try std.testing.expectEqual(@as(?*TileInfo, null), actual);
            }
        }
    }

    const expected_names = [_][]const u8{ "test-layout", "left", "left-sub", "middle", "right", "right-sub", "sub2" };
    const expected_parents = [_]?[]const u8{ null, "test-layout", "left", "test-layout", "test-layout", "right", "right-sub" };
    for (expected_names, expected_parents, tile_infos.tile_infos) |expected, expected_parent_opt, actual| {
        try std.testing.expectEqualStrings(expected, actual.tile.name);
        if (expected_parent_opt) |expected_parent| {
            try std.testing.expectEqualStrings(expected_parent, actual.parent_tile.?.tile.name);
        } else {
            try std.testing.expectEqual(@as(?*TileInfo, null), actual.parent_tile);
        }
    }
}

fn determineAmountViewsPerTile(view_count: u32, tile_infos: *TileInfos) void {
    var views_left_to_assign = view_count;
    for (tile_infos.order_suborder_map) |suborder_map| {
        var views_left_to_assign_with_this_order: u32 = 0;
        for (suborder_map) |tile_info_opt| if (tile_info_opt) |tile_info| {
            if (tile_info.tile.max_views) |max_views| {
                if (max_views != 0) {
                    views_left_to_assign_with_this_order +|= max_views;
                }
            } else {
                views_left_to_assign_with_this_order = std.math.maxInt(u32);
            }
        };
        views_left_to_assign_with_this_order = @min(views_left_to_assign, views_left_to_assign_with_this_order);

        while (views_left_to_assign_with_this_order > 0) {
            for (suborder_map) |tile_info_opt| if (tile_info_opt) |tile_info| {
                if (tile_info.tile.max_views) |max_views| {
                    if (tile_info.views >= max_views) continue;
                }
                tile_info.views += 1;
                tile_info.views_recursive += 1;
                var parent_tile_info_opt = tile_info.parent_tile;
                while (parent_tile_info_opt) |parent_tile_info| : (parent_tile_info_opt = parent_tile_info.parent_tile) {
                    parent_tile_info.views_recursive += 1;
                }
                views_left_to_assign -= 1;
                views_left_to_assign_with_this_order -= 1;
                if (views_left_to_assign_with_this_order <= 0) break;
            };
        }
    }
}

fn testDetermineAmountViewsPerTile(allocator: std.mem.Allocator, view_count: u32, expected_views_itemss: [3][2]?u32, expected_views_rec_root: u32, expected_views_rec_left: u32, expected_views_rec_right: u32) !void {
    var tile = try createTestLayout(allocator);
    defer tile.deinit();

    var tile_infos = try buildFillingInfo(allocator, &tile);
    defer tile_infos.deinit();

    determineAmountViewsPerTile(view_count, &tile_infos);

    for (expected_views_itemss, tile_infos.order_suborder_map) |expected_views_items, actual_suborder_map| {
        for (expected_views_items, actual_suborder_map) |expected_opt, actual| {
            if (expected_opt) |expected_views| {
                try std.testing.expectEqual(expected_views, actual.?.views);
            } else {
                try std.testing.expectEqual(@as(?*TileInfo, null), actual);
            }
        }
    }
    // root tile
    try std.testing.expectEqualStrings("test-layout", tile_infos.tile_infos[0].tile.name);
    try std.testing.expectEqual(expected_views_rec_root, tile_infos.tile_infos[0].views_recursive);
    // "left" tile
    try std.testing.expectEqualStrings("left", tile_infos.tile_infos[1].tile.name);
    try std.testing.expectEqual(expected_views_rec_left, tile_infos.tile_infos[1].views_recursive);
    // "right" tile
    try std.testing.expectEqualStrings("right", tile_infos.tile_infos[4].tile.name);
    try std.testing.expectEqual(expected_views_rec_right, tile_infos.tile_infos[4].views_recursive);
}

test "determineAmountViewsPerTile 2" {
    const expected_views_itemss = [3][2]?u32{
        .{
            null,
            null,
        },
        .{
            1, // test-layout (max 1)
            1, // sub2 (max 2)
        },
        .{
            0, // left-sub
            0, // middle
        },
    };
    try testDetermineAmountViewsPerTile(std.testing.allocator, 2, expected_views_itemss, 2, 0, 1);
}

test "determineAmountViewsPerTile 3" {
    const expected_views_itemss = [3][2]?u32{
        .{
            null,
            null,
        },
        .{
            1, // test-layout (max 1)
            2, // sub2 (max 2)
        },
        .{
            0, // left-sub
            0, // middle
        },
    };
    try testDetermineAmountViewsPerTile(std.testing.allocator, 3, expected_views_itemss, 3, 0, 2);
}

test "determineAmountViewsPerTile 4" {
    const expected_views_itemss = [3][2]?u32{
        .{
            null,
            null,
        },
        .{
            1, // test-layout (max 1)
            2, // sub2 (max 2)
        },
        .{
            1, // left-sub
            0, // middle
        },
    };
    try testDetermineAmountViewsPerTile(std.testing.allocator, 4, expected_views_itemss, 4, 1, 2);
}

test "determineAmountViewsPerTile 5" {
    const expected_views_itemss = [3][2]?u32{
        .{
            null,
            null,
        },
        .{
            1, // test-layout (max 1)
            2, // sub2 (max 2)
        },
        .{
            1, // left-sub
            1, // middle
        },
    };
    try testDetermineAmountViewsPerTile(std.testing.allocator, 5, expected_views_itemss, 5, 1, 2);
}

test "determineAmountViewsPerTile 6" {
    const expected_views_itemss = [3][2]?u32{
        .{
            null,
            null,
        },
        .{
            1, // test-layout (max 2)
            2, // sub2 (max 2)
        },
        .{
            2, // left-sub
            1, // middle
        },
    };
    try testDetermineAmountViewsPerTile(std.testing.allocator, 6, expected_views_itemss, 6, 2, 2);
}

test "determineAmountViewsPerTile 7" {
    const expected_views_itemss = [3][2]?u32{
        .{
            null,
            null,
        },
        .{
            1, // test-layout (max 2)
            2, // sub2 (max 2)
        },
        .{
            2, // left-sub
            2, // middle
        },
    };
    try testDetermineAmountViewsPerTile(std.testing.allocator, 7, expected_views_itemss, 7, 2, 2);
}

fn subtileDimensions(stretch: u32, stretch_before: u32, stretch_total: u32, elements_before: u32, elements_total: u32, padding: u31, margin: u32, parent_tile_info: *TileInfo) Dimensions {
    const parent_tile = parent_tile_info.tile;
    // The parent's dimensions must have been initialized already
    const parent_dimensions = parent_tile_info.dimensions.?;

    const parent_before = switch (parent_tile.typ) {
        .hsplit => parent_dimensions.x,
        .vsplit => parent_dimensions.y,
        .overlay => parent_dimensions.x,
    };
    const parent_size = switch (parent_tile.typ) {
        .hsplit => parent_dimensions.width,
        .vsplit => parent_dimensions.height,
        .overlay => parent_dimensions.width,
    };

    const stretch_f: f32 = @floatFromInt(stretch);
    const stretch_before_f: f32 = @floatFromInt(stretch_before);
    const stretch_total_f: f32 = @floatFromInt(stretch_total);

    const parent_size_without_padding: f32 = @floatFromInt(parent_size - padding * (elements_total - 1));

    const padding_before: i32 = @intCast(padding * elements_before);
    const before_from_elements: i32 = @intFromFloat(stretch_before_f / stretch_total_f * parent_size_without_padding);
    const before: i32 = parent_before + padding_before + before_from_elements + @as(i32, @intCast(margin));

    const size: u32 = (
        if (elements_before + 1 < elements_total) @intFromFloat(stretch_f / stretch_total_f * parent_size_without_padding) else
        // Make things line up pixel-perfect
        parent_size - @as(u32, @intCast(padding_before + before_from_elements))
    ) - margin * 2;

    return switch (parent_tile.typ) {
        .hsplit => Dimensions{
            .x = before,
            .y = parent_dimensions.y + margin,
            .width = size,
            .height = parent_dimensions.height - margin * 2,
        },
        .vsplit => Dimensions{
            .x = parent_dimensions.x + margin,
            .y = before,
            .width = parent_dimensions.width - margin * 2,
            .height = size,
        },
        .overlay => Dimensions{
            .x = parent_dimensions.x + margin,
            .y = parent_dimensions.y + margin,
            .width = parent_dimensions.width - margin * 2,
            .height = parent_dimensions.height - margin * 2,
        },
    };
}

fn determinePadding(tile_info: *TileInfo) u31 {
    if (tile_info.tile.padding) |padding| {
        return padding;
    } else if (tile_info.parent_tile) |parent_tile| {
        return determinePadding(parent_tile);
    } else {
        return 0;
    }
}

fn determineViewSubtileDimensions(tile_info: *TileInfo) !void {
    var views_dimensions = try tile_info.allocator.alloc(Dimensions, tile_info.views);
    tile_info.views_dimensions = views_dimensions;

    var stretch_total: u32 = tile_info.views * VIEW_STRETCH;
    for (tile_info.tile.subtiles.items) |*subtile| stretch_total += subtile.stretch;
    const elements_total = tile_info.views + @as(u32, @intCast(tile_info.tile.subtiles.items.len));
    var stretch_before: u32 = 0;
    var elements_before: u32 = 0;
    const padding = determinePadding(tile_info);
    for (tile_info.subtiles) |subtile| {
        subtile.dimensions = subtileDimensions(subtile.tile.stretch, stretch_before, stretch_total, elements_before, elements_total, padding, subtile.tile.margin, tile_info);
        stretch_before += subtile.tile.stretch;
        elements_before += 1;
    }
    for (0..tile_info.views) |i| {
        views_dimensions[i] = subtileDimensions(VIEW_STRETCH, stretch_before, stretch_total, elements_before, elements_total, padding, 0, tile_info);
        stretch_before += VIEW_STRETCH;
        elements_before += 1;
    }
    for (tile_info.subtiles) |subtile| {
        try determineViewSubtileDimensions(subtile);
    }
}

fn determineViewDimensions(allocator: std.mem.Allocator, view_count: u32, tile_infos: *TileInfos) ![]Dimensions {
    var view_dimensions = try allocator.alloc(Dimensions, view_count);
    errdefer allocator.free(view_dimensions);

    var i: u32 = 0;
    for (tile_infos.order_suborder_map) |suborder_map| {
        for (suborder_map) |tile_info_opt| if (tile_info_opt) |tile_info| {
            if (tile_info.views_dimensions) |tile_view_dimensions| {
                for (tile_view_dimensions) |dimensions| {
                    view_dimensions[i] = dimensions;
                    i += 1;
                }
            }
        };
    }
    std.debug.assert(i <= view_count);
    view_dimensions = try allocator.realloc(view_dimensions, i);

    return view_dimensions;
}

pub fn layout(allocator: std.mem.Allocator, root_tile: *Tile, view_count: u32, usable_width: u31, usable_height: u31) ![]Dimensions {
    var tile_infos = try buildFillingInfo(allocator, root_tile);
    defer tile_infos.deinit();

    determineAmountViewsPerTile(view_count, &tile_infos);

    var root_tile_info = &tile_infos.tile_infos[0];
    root_tile_info.dimensions = Dimensions{
        .x = @intCast(root_tile.margin),
        .y = @intCast(root_tile.margin),
        .width = usable_width - 2 * root_tile.margin,
        .height = usable_height - 2 * root_tile.margin,
    };
    try determineViewSubtileDimensions(root_tile_info);

    return determineViewDimensions(allocator, view_count, &tile_infos);
}
