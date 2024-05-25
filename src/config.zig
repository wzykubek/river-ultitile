const std = @import("std");
const assert = std.debug.assert;
const util = @import("./util.zig");

pub const TileType = enum {
    hsplit,
    vsplit,
};

pub const Tile = struct {
    allocator: std.mem.Allocator,

    typ: TileType,
    name: []const u8,

    /// Size (ratio; relative to the sizes of the other subtiles in the tile; ignored for the root
    /// tile)
    stretch: u32,
    // /// Maximum size (px)
    // max_size: ?u31,
    // /// Minimum size (px)
    // min_size: u32,
    /// Padding between contents (px)
    padding: ?u31,

    order: u32,
    suborder: u32,
    max_views: ?u31,

    subtiles: std.ArrayList(Tile),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Tile {
        return Tile{
            .allocator = allocator,

            .typ = .hsplit,
            .name = try allocator.dupe(u8, name),

            .stretch = 1,
            .padding = null,

            .order = 0,
            .suborder = 0,
            .max_views = 0,

            .subtiles = try std.ArrayList(Tile).initCapacity(allocator, 3),
        };
    }

    pub fn deinit(self: *Tile) void {
        self.allocator.free(self.name);
        for (self.subtiles.items) |*subtile| {
            subtile.deinit();
        }
        self.subtiles.deinit();
    }

    pub fn addSubtile(self: *Tile, name: []const u8) !*Tile {
        if (self.getSubtile(name) != null) return error.TileAlreadyExists;
        const subtile = try self.subtiles.addOne();
        subtile.* = try Tile.init(self.allocator, name);
        return subtile;
    }

    pub fn getSubtile(self: *Tile, name: []const u8) ?*Tile {
        for (self.subtiles.items) |*subtile| {
            if (std.mem.eql(u8, subtile.name, name)) {
                return subtile;
            }
        } else {
            return null;
        }
    }
};

pub const LayoutSpecificationMap = std.hash_map.StringHashMap(*Tile);

pub const Result = util.Result(void, []const u8);

const StringTokenIterator = std.mem.TokenIterator(u8, .scalar);

pub const Config = struct {
    allocator: std.mem.Allocator,

    layout_specifications: LayoutSpecificationMap,
    output__active_layout_specification__map: std.hash_map.AutoHashMap(u32, ?[]const u8),

    default_layout: ?*[]const u8,

    pub fn init(allocator: std.mem.Allocator) Config {
        return Config{
            .allocator = allocator,
            .layout_specifications = LayoutSpecificationMap.init(allocator),
            .output__active_layout_specification__map = std.hash_map.AutoHashMap(u32, ?[]const u8).init(allocator),
            .default_layout = null,
        };
    }

    pub fn deinit(self: *Config) void {
        var iterator = self.layout_specifications.iterator();
        while (iterator.next()) |entry| {
            self.layout_specifications.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.layout_specifications.allocator.destroy(entry.value_ptr.*);
        }
        self.layout_specifications.deinit();

        self.output__active_layout_specification__map.deinit();
    }

    pub fn executeCommand(self: *Config, command: []const u8) !Result {
        var parts: StringTokenIterator = std.mem.tokenizeScalar(u8, command, ' ');
        var part = parts.next() orelse return Result{ .err = "Empty command" };

        if (std.mem.eql(u8, part, "new")) {
            return executeCommandNew(&parts, &self.layout_specifications);
        } else if (std.mem.eql(u8, part, "default")) {
            return executeCommandDefault(&parts, self);
        } else {
            return Result{ .err = "Unrecognized first word of command" };
        }
    }

    pub fn getLayoutSpecification(self: *Config, output_name: u32) ?*Tile {
        const layout_specification_name: []const u8 = (self.output__active_layout_specification__map.get(output_name) orelse return null) orelse return null;
        return self.layout_specifications.get(layout_specification_name);
    }

    pub fn getDefaultLayoutSpecification(self: *Config) ?*Tile {
        return self.layout_specifications.get((self.default_layout orelse return null).*) orelse return null;
    }
};

fn executeCommandNew(parts: *StringTokenIterator, layout_specifications: *LayoutSpecificationMap) !Result {
    var part = parts.next() orelse return Result{ .err = "Premature end of command after 'new'" };

    if (std.mem.eql(u8, part, "layout")) {
        return executeCommandNewLayout(parts, layout_specifications);
    } else if (std.mem.eql(u8, part, "tile")) {
        return executeCommandNewTile(parts, layout_specifications);
    } else {
        return Result{ .err = "Unrecognized word in command after 'new'" };
    }
}

fn executeCommandNewLayout(parts: *StringTokenIterator, layout_specifications: *LayoutSpecificationMap) !Result {
    var layout_name = parts.next() orelse return Result{ .err = "Premature end of command after 'layout'" };

    if (std.mem.indexOfScalar(u8, layout_name, '.') != null) {
        return Result{ .err = "Layout name contains illegal character '.'" };
    }

    const layout_name_owned = try layout_specifications.allocator.dupe(u8, layout_name);
    errdefer layout_specifications.allocator.free(layout_name_owned);
    const layout_get_or_put: std.hash_map.StringHashMap(*Tile).GetOrPutResult = try layout_specifications.getOrPut(layout_name_owned);
    if (layout_get_or_put.found_existing) {
        layout_specifications.allocator.free(layout_name_owned);
        return Result{ .err = "Layout with this name already exists" };
    }

    var tile = try layout_specifications.allocator.create(Tile);
    errdefer layout_specifications.allocator.destroy(tile);

    tile.* = try Tile.init(layout_specifications.allocator, layout_name);
    switch (parseLayoutOptions(parts, tile)) {
        .err => |err| return Result{ .err = err },
        .ok => {},
    }
    layout_get_or_put.value_ptr.* = tile;

    return Result{ .ok = {} };
}

fn executeCommandNewTile(parts: *StringTokenIterator, layout_specifications: *LayoutSpecificationMap) !Result {
    const full_tile_name = parts.next() orelse return Result{ .err = "Premature end of command after 'tile'" };

    var tile_name_parts_iterator = std.mem.tokenizeScalar(u8, full_tile_name, '.');
    const layout_name = tile_name_parts_iterator.next() orelse return Result{ .err = "Premature end of command after 'tile'" };

    const root_tile = layout_specifications.get(layout_name) orelse return Result{ .err = "Layout does not exist" };
    var tile: *Tile = root_tile;

    const tile_name_parts = try util.tokenIteratorAsSlice(u8, .scalar, layout_specifications.allocator, &tile_name_parts_iterator);
    defer layout_specifications.allocator.free(tile_name_parts);
    if (tile_name_parts.len < 1) return Result{ .err = "Missing tile name after layout name" };
    for (tile_name_parts[0 .. tile_name_parts.len - 1]) |tile_name| {
        tile = tile.getSubtile(tile_name) orelse return Result{ .err = "Ancestor tile not found (create parent tiles first)" };
    }
    const tile_name = tile_name_parts[tile_name_parts.len - 1];
    var subtile = tile.addSubtile(tile_name) catch |err| switch (err) {
        error.TileAlreadyExists => return Result{ .err = "Tile exists already" },
        else => |leftover_err| return leftover_err,
    };

    return parseLayoutOptions(parts, subtile);
}

fn executeCommandDefault(parts: *StringTokenIterator, cfg: *Config) !Result {
    var part = parts.next() orelse return Result{ .err = "Premature end of command after 'default'" };

    if (std.mem.eql(u8, part, "layout")) {
        return executeCommandDefaultLayout(parts, cfg);
    } else {
        return Result{ .err = "Unrecognized word in command after 'default'" };
    }
}

fn executeCommandDefaultLayout(parts: *StringTokenIterator, cfg: *Config) !Result {
    var layout_name = parts.next() orelse return Result{ .err = "Premature end of command after 'layout'" };

    if (cfg.layout_specifications.getKeyPtr(layout_name)) |layout_name_ptr| {
        cfg.default_layout = layout_name_ptr;
        return Result{ .ok = {} };
    } else {
        return Result{ .err = "Layout doesn't exist yet (create layout first)" };
    }
}

fn parseLayoutOptions(parts: *StringTokenIterator, tile: *Tile) Result {
    while (parts.next()) |part| {
        var option_parts = std.mem.tokenizeScalar(u8, part, '=');
        const option_name = option_parts.next().?;
        const option_value = option_parts.next() orelse return Result{ .err = "Missing option value" };
        if (option_parts.next() != null) return Result{ .err = "Spurious '=' in option" };

        if (std.mem.eql(u8, option_name, "type")) {
            if (std.mem.eql(u8, option_value, "hsplit")) {
                tile.typ = TileType.hsplit;
            } else if (std.mem.eql(u8, option_value, "vsplit")) {
                tile.typ = TileType.vsplit;
            } else return Result{ .err = "Unrecognized tile type (expecting one of 'hsplit', 'vsplit')" };
        } else if (std.mem.eql(u8, option_name, "stretch")) {
            tile.stretch = std.fmt.parseInt(u31, option_value, 10) catch
                return Result{ .err = "Couldn't parse stretch value as positive integer" };
        } else if (std.mem.eql(u8, option_name, "padding")) {
            if (std.mem.eql(u8, option_value, "inherit")) {
                tile.padding = null;
            } else {
                tile.padding = std.fmt.parseInt(u31, option_value, 10) catch
                    return Result{ .err = "Couldn't parse max-views value as positive integer or 'inherit'" };
            }
        } else if (std.mem.eql(u8, option_name, "order")) {
            tile.order = std.fmt.parseInt(u31, option_value, 10) catch
                return Result{ .err = "Couldn't parse order value as positive integer" };
            // If tiling order is being set, the user wants this tile to hold views. We set
            // max-views to unlimited here so the user doesn't have to
            if (tile.max_views) |max_views| {
                if (max_views == 0) tile.max_views = null;
            }
        } else if (std.mem.eql(u8, option_name, "suborder")) {
            tile.suborder = std.fmt.parseInt(u31, option_value, 10) catch
                return Result{ .err = "Couldn't parse suborder value as positive integer" };
        } else if (std.mem.eql(u8, option_name, "max-views")) {
            if (std.mem.eql(u8, option_value, "unlimited")) {
                tile.max_views = null;
            } else {
                tile.max_views = std.fmt.parseInt(u31, option_value, 10) catch
                    return Result{ .err = "Couldn't parse max-views value as positive integer or 'unlimited'" };
            }
        } else return Result{ .err = "Unrecognized option" };
    }
    return Result{ .ok = {} };
}

test {
    var cfg = Config.init(std.testing.allocator);
    defer cfg.deinit();
    var layout_specifications = &cfg.layout_specifications;

    const result1 = try cfg.executeCommand("new layout main-left type=hsplit padding=5");
    try std.testing.expectEqual(Result{ .ok = {} }, result1);
    const result2 = try cfg.executeCommand("new tile main-left.left type=vsplit stretch=25 order=2");
    try std.testing.expectEqual(Result{ .ok = {} }, result2);
    const result3 = try cfg.executeCommand("new tile main-left.main type=vsplit stretch=25 order=1 suborder=2 max-views=1");
    try std.testing.expectEqual(Result{ .ok = {} }, result3);
    const result4 = try cfg.executeCommand("new tile main-left.main");
    try std.testing.expectEqualStrings("Tile exists already", result4.err);
    const result5 = try cfg.executeCommand("new tile main-left.main.submain order=1 suborder=1 max-views=1");
    try std.testing.expectEqual(Result{ .ok = {} }, result5);
    const result6 = try cfg.executeCommand("default layout main-left");
    try std.testing.expectEqual(Result{ .ok = {} }, result6);
    const result7 = try cfg.initComplete();
    try std.testing.expectEqual(Result{ .ok = {} }, result7);

    const mainleft_root = layout_specifications.get("main-left").?;
    try std.testing.expectEqual(TileType.hsplit, mainleft_root.typ);
    try std.testing.expectEqual(@as(u32, 1), mainleft_root.stretch);
    try std.testing.expectEqual(@as(?u31, 5), mainleft_root.padding);
    try std.testing.expectEqual(@as(?u31, 0), mainleft_root.max_views);

    try std.testing.expectEqual(@as(usize, 2), mainleft_root.subtiles.items.len);

    const mainleft_left = mainleft_root.getSubtile("left").?;
    try std.testing.expectEqual(TileType.vsplit, mainleft_left.typ);
    try std.testing.expectEqual(@as(u32, 25), mainleft_left.stretch);
    try std.testing.expectEqual(@as(?u31, null), mainleft_left.max_views);
    try std.testing.expectEqual(@as(u32, 2), mainleft_left.order);
    try std.testing.expectEqual(@as(u32, 0), mainleft_left.suborder);

    const mainleft_main = mainleft_root.getSubtile("main").?;
    try std.testing.expectEqual(TileType.vsplit, mainleft_main.typ);
    try std.testing.expectEqual(@as(u32, 25), mainleft_main.stretch);
    try std.testing.expectEqual(@as(?u31, 1), mainleft_main.max_views);
    try std.testing.expectEqual(@as(u32, 1), mainleft_main.order);
    try std.testing.expectEqual(@as(u32, 2), mainleft_main.suborder);

    const mainleft_submain = mainleft_main.getSubtile("submain").?;
    try std.testing.expectEqual(@as(?u31, 1), mainleft_submain.max_views);
    try std.testing.expectEqual(@as(u32, 1), mainleft_submain.order);
    try std.testing.expectEqual(@as(u32, 1), mainleft_submain.suborder);
}
