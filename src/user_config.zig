const std = @import("std");

const config = @import("config.zig");

pub fn setDefaultVariables(variables: *config.Variables) !void {
    try variables.putDefault("layout", config.Var{ .string = try variables.allocator.dupe(u8, "main") });
    try variables.putDefault("main-size", config.Var{ .integer = 60 });
    try variables.putDefault("main-size-if-only-centered-main", config.Var{ .integer = 80 });
    try variables.putDefault("main-count", config.Var{ .integer = 1 });
}

pub const Layout = enum { main, hstack, vstack, monocle };

pub fn layoutSpecification(allocator: std.mem.Allocator, variables: *config.Variables, view_count: u32, usable_width: u32, usable_height: u32, output_name: u32, tags: u32) !config.Tile {
    _ = usable_height;

    const layout = std.meta.stringToEnum(Layout, variables.getString("layout", tags, output_name) orelse return error.UnknownVariable) orelse return error.UnknownLayout;

    // Minimum width to enable the widescreen mode of the main layout
    const min_width_for_center_main = 2200;

    const inner_gaps = 0;
    const outer_gaps = 0;

    // Smart gaps: return just a simple margin-less tile if there's only one view and the
    // widescreen mode is not to be enabled. If you want gaps around your view even if it's the
    // only view, you can comment this out or add a margin to this root tile
    if (view_count == 1 and (layout != .main or usable_width < min_width_for_center_main)) {
        var root = try config.Tile.init(allocator, "root");
        root.max_views = null;
        return root;
    }

    // To add a new layout, just add it to the Layout enum above and write code in this switch
    switch (layout) {
        .main => {
            const main_count: u31 = @max(0, variables.getInteger("main-count", tags, output_name) orelse return error.UnknownVariable);

            const normal_main_size: u32 = @min(100, @max(0, variables.getInteger("main-size", tags, output_name) orelse return error.UnknownVariable));
            const main_size_if_only_centered_main: u31 = @min(100, @max(0, variables.getInteger("main-size-if-only-centered-main", tags, output_name) orelse return error.UnknownVariable));
            const applicable_main_size = if (view_count > main_count or usable_width < min_width_for_center_main) normal_main_size else main_size_if_only_centered_main;
            // In the widescreen mode of the main layout, the size of the main tile is dependent on
            // whether or not there are only main views. If you don't like that, comment the code
            // above and uncomment the code below
            //const applicable_main_size = normal_main_size;

            var root = try config.Tile.init(allocator, "root");
            root.margin = outer_gaps;
            root.padding = inner_gaps;

            // Left, only in widescreen mode
            if (usable_width >= min_width_for_center_main) {
                var left = try root.addSubtile("left");
                left.max_views = null;
                left.order = 1;
                left.suborder = 0;
                left.stretch = 100 -| applicable_main_size;
                left.typ = config.TileType.vsplit;
            }

            // Main
            var main = try root.addSubtile("main");
            main.typ = .vsplit;
            main.max_views = main_count;
            main.order = 0;
            main.stretch = applicable_main_size;

            // Right
            if (usable_width >= min_width_for_center_main or view_count > main_count) {
                var right = try root.addSubtile("right");
                right.max_views = null;
                right.order = 1;
                right.suborder = 1;
                right.stretch = 100 -| applicable_main_size;
                right.typ = config.TileType.vsplit;
            }

            return root;
        },

        .hstack => {
            var root = try config.Tile.init(allocator, "root");
            root.max_views = null;
            root.margin = outer_gaps;
            root.padding = inner_gaps;
            return root;
        },

        .vstack => {
            var root = try config.Tile.init(allocator, "root");
            root.typ = .vsplit;
            root.max_views = null;
            root.margin = outer_gaps;
            root.padding = inner_gaps;
            return root;
        },

        .monocle => {
            var root = try config.Tile.init(allocator, "root");
            root.typ = .overlay;
            root.max_views = null;
            return root;
        },
    }
}
