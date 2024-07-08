// river-ultitile <https://sr.ht/~midgard/river-ultitile>
// See main.zig and COPYING for copyright info

const std = @import("std");
const builtin = @import("builtin");
const util = @import("util.zig");
const main = @import("main.zig");

/// The stretch value used for views and as default for tiles
pub const default_stretch: u32 = 100;

pub const TileType = enum {
    hsplit,
    vsplit,
    overlay,
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
    /// Margin around tile (px)
    margin: u32,

    order: u32,
    suborder: u32,
    max_views: ?u31,

    subtiles: std.ArrayList(Tile),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Tile {
        return Tile{
            .allocator = allocator,

            .typ = .hsplit,
            .name = try allocator.dupe(u8, name),

            .stretch = default_stretch,
            .padding = null,
            .margin = 0,

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

    /// Does not take ownership of name
    pub fn addSubtile(self: *Tile, name: []const u8) !*Tile {
        if (self.getSubtile(name) != null) return error.TileAlreadyExists;
        const subtile_ptr = try self.subtiles.addOne();
        subtile_ptr.* = try Tile.init(self.allocator, name);
        return subtile_ptr;
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

pub const Result = util.Result(void, []const u8);

const StringTokenIterator = std.mem.TokenIterator(u8, .scalar);

pub const OutputAndTags = struct {
    output_name: ?u32 = null,
    tags: ?u32 = null,
};

/// Find the lowest tag that's set in a tag bitmask
pub fn dominantTag(tags: u32) u32 {
    const trailing_zeros = @ctz(tags);
    if (trailing_zeros >= 32) return 0;
    return @as(u32, 1) << @as(u5, @intCast(trailing_zeros));
}

pub const VarTag = enum {
    integer,
    string,
    boolean,
};
pub const Var = union(VarTag) {
    integer: i32,
    string: []const u8,
    boolean: bool,

    fn deinit(self: *const Var, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            else => {},
        }
    }
};

pub const Operator = enum {
    @"=",
    @"-=",
    @"+=",
    @"@",
};

pub const Variable = struct {
    name: []const u8,
    value: Var,
    tag: ?u32,
    output: ?u32,

    pub fn deinit(self: *Variable, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.value.deinit(allocator);
    }
};

pub const VariablesHashMap = std.hash_map.StringHashMap(Var);
pub const Variables = struct {
    allocator: std.mem.Allocator,
    data: std.SinglyLinkedList(Variable),

    pub fn init(allocator: std.mem.Allocator) Variables {
        return Variables{
            .allocator = allocator,
            .data = std.SinglyLinkedList(Variable){},
        };
    }

    pub fn deinit(self: *Variables) void {
        while (self.data.popFirst()) |node| {
            node.data.deinit(self.allocator);
            self.allocator.destroy(node);
        }
    }

    pub fn get(self: *Variables, name: []const u8, tags: ?u32, output: ?u32) ?Var {
        const tag = if (tags) |t| dominantTag(t) else null;
        var max_specificity_found: u8 = 0;
        var value_found: ?Var = null;
        var maybe_node = self.data.first;
        while (maybe_node) |node| : (maybe_node = node.next) {
            const item = &node.data;
            var specificity: u8 = 0;
            if (item.output) |item_output| {
                if (item_output != output) continue;
                specificity |= 1 << 0;
            }
            if (item.tag) |item_tag| {
                if (item_tag != tag) continue;
                specificity |= 1 << 1;
            }
            if (specificity < max_specificity_found) continue;
            if (!std.mem.eql(u8, item.name, name)) continue;
            max_specificity_found = specificity;
            value_found = item.value;
        }
        return value_found;
    }

    pub fn getString(self: *Variables, name: []const u8, tags: u32, output: u32) ?[]const u8 {
        const maybe_variable = self.get(name, tags, output);
        if (maybe_variable) |variable| {
            return switch (variable) {
                .string => |value| value,
                else => null,
            };
        } else return null;
    }

    pub fn getInteger(self: *Variables, name: []const u8, tags: u32, output: u32) ?i32 {
        const maybe_variable = self.get(name, tags, output);
        if (maybe_variable) |variable| {
            return switch (variable) {
                .integer => |value| value,
                else => null,
            };
        } else return null;
    }

    pub fn getBoolean(self: *Variables, name: []const u8, tags: u32, output: u32) ?bool {
        const maybe_variable = self.get(name, tags, output);
        if (maybe_variable) |variable| {
            return switch (variable) {
                .boolean => |value| value,
                else => null,
            };
        } else return null;
    }

    /// Takes ownership of value.string, which must have used our allocator
    pub fn put(self: *Variables, name: []const u8, tags: ?u32, output: ?u32, value: Var) !void {
        const tag = if (tags) |_tags| dominantTag(_tags) else null;
        var maybe_node = self.data.first;
        while (maybe_node) |node| : (maybe_node = node.next) {
            const item = &node.data;
            if (item.output == output and item.tag == tag and std.mem.eql(u8, item.name, name)) {
                item.value.deinit(self.allocator);
                item.value = value;
                break;
            }
        } else {
            const node = try self.allocator.create(std.SinglyLinkedList(Variable).Node);
            node.* = .{ .data = Variable{
                .name = try self.allocator.dupe(u8, name),
                .output = output,
                .tag = tag,
                .value = value,
            } };
            self.data.prepend(node);
        }
    }

    /// Takes ownership of value.string, which must have used our allocator
    pub fn putDefault(self: *Variables, name: []const u8, value: Var) !void {
        try self.put(name, null, null, value);
    }

    pub fn remove(self: *Variables, name: []const u8, tags: ?u32, output: ?u32) void {
        const tag = if (tags) |_tags| dominantTag(_tags) else null;
        var maybe_node = self.data.first;
        while (maybe_node) |node| : (maybe_node = node.next) {
            const item = &node.data;
            if (item.output == output and item.tag == tag and std.mem.eql(u8, item.name, name)) {
                item.deinit(self.allocator);
                self.data.remove(node);
                break;
            }
        }
    }

    pub fn removeAllLocal(self: *Variables, name: []const u8) void {
        var maybe_node = self.data.first;
        while (maybe_node) |node| : (maybe_node = node.next) {
            const item = &node.data;
            if (item.output != null and item.tag != null and std.mem.eql(u8, item.name, name)) {
                item.deinit(self.allocator);
                self.data.remove(node);
                break;
            }
        }
    }
};

pub const Config = struct {
    allocator: std.mem.Allocator,

    variables: Variables,

    pub fn init(allocator: std.mem.Allocator) Config {
        return Config{
            .allocator = allocator,
            .variables = Variables.init(allocator),
        };
    }

    pub fn deinit(self: *Config) void {
        self.variables.deinit();
    }

    pub fn executeCommand(self: *Config, command: []const u8, current_output_tag: OutputAndTags) !Result {
        var parts: StringTokenIterator = std.mem.tokenizeScalar(u8, command, ' ');
        const part = parts.next() orelse return Result{ .err = "Empty command" };

        if (std.mem.eql(u8, part, "set")) {
            return executeCommandSet(&parts, &self.variables, current_output_tag);
        } else if (std.mem.eql(u8, part, "clear-local")) {
            return executeCommandClearLocal(&parts, &self.variables, current_output_tag);
        } else if (std.mem.eql(u8, part, "clear-all-local")) {
            return executeCommandClearAllLocal(&parts, &self.variables);
        } else {
            return Result{ .err = "Unrecognized first word of command" };
        }
    }
};

fn executeCommandSet(parts: *StringTokenIterator, variables: *Variables, current_output_tag: OutputAndTags) !Result {
    var variable_type_str = parts.next() orelse return Result{ .err = "Premature end of command after 'set', expecting type or 'global'" };
    var global = false;
    if (std.mem.eql(u8, variable_type_str, "global")) {
        global = true;
        variable_type_str = parts.next() orelse return Result{ .err = "Premature end of command after 'set', expecting type" };
    }
    const variable_name = parts.next() orelse return Result{ .err = "Premature end of command after variable type, expecting name" };
    const operator_str = parts.next() orelse return Result{ .err = "Premature end of command after variable name, expecting operator" };

    const variable_type = std.meta.stringToEnum(VarTag, variable_type_str) orelse return Result{ .err = "Unknown variable type" };

    const operator = std.meta.stringToEnum(Operator, operator_str) orelse return Result{ .err = "Unknown operator" };

    const focused_output = if (global) null else current_output_tag.output_name;
    const current_tags = if (global) null else current_output_tag.tags;

    const old_value_opt = variables.get(variable_name, current_tags, focused_output);
    if (old_value_opt) |old_value| {
        if (variable_type != @as(VarTag, old_value)) {
            return Result{ .err = "Type of variable cannot be changed after initial assignment" };
        }
    }

    const variable_value = switch (try newVariableValue(variables.allocator, variable_type, operator, parts, old_value_opt)) {
        .ok => |val| val,
        .err => |str| return Result{ .err = str },
    };
    errdefer variable_value.deinit(variables.allocator);

    try variables.put(variable_name, current_tags, focused_output, variable_value);

    return Result{ .ok = {} };
}

fn executeCommandClearLocal(parts: *StringTokenIterator, variables: *Variables, current_output_tag: OutputAndTags) Result {
    const variable_name = parts.next() orelse return Result{ .err = "Premature end of command after 'clear-local', expecting name" };

    if (current_output_tag.output_name == null) return Result{ .err = "Focused output is not registered" };

    variables.remove(variable_name, current_output_tag.tags, current_output_tag.output_name);

    return Result{ .ok = {} };
}

fn executeCommandClearAllLocal(parts: *StringTokenIterator, variables: *Variables) Result {
    const variable_name = parts.next() orelse return Result{ .err = "Premature end of command after 'clear-all-local', expecting name" };

    variables.removeAllLocal(variable_name);

    return Result{ .ok = {} };
}

fn newVariableValue(allocator: std.mem.Allocator, variable_type: VarTag, operator: Operator, parts: *StringTokenIterator, old_value_opt: ?Var) !util.Result(Var, []const u8) {
    return switch (variable_type) {
        .boolean => newVariableValueBoolean(operator, parts, old_value_opt),
        .integer => newVariableValueInteger(operator, parts, old_value_opt),
        .string => try newVariableValueString(allocator, operator, parts, old_value_opt),
    };
}

fn parseBoolean(value_str: []const u8) ?bool {
    return if (std.mem.eql(u8, value_str, "true")) true else if (std.mem.eql(u8, value_str, "false")) false else null;
}

fn newVariableValueBoolean(operator: Operator, parts: *StringTokenIterator, old_value_opt: ?Var) util.Result(Var, []const u8) {
    const value_str = parts.next() orelse return .{ .err = "Premature end of command after operator, expecting value" };
    const parsed_value = parseBoolean(value_str) orelse return .{ .err = "Invalid boolean value" };
    switch (operator) {
        .@"=" => {
            return .{ .ok = Var{ .boolean = parsed_value } };
        },
        .@"@" => {
            if (old_value_opt) |old_value| {
                std.debug.assert(@as(VarTag, old_value) == VarTag.boolean);
                return .{ .ok = Var{ .boolean = !old_value.boolean } };
            } else {
                return .{ .ok = Var{ .boolean = parsed_value } };
            }
        },
        else => return .{ .err = "Unsupported operator for boolean variable, supported are = and @" },
    }
}

fn newVariableValueInteger(operator: Operator, parts: *StringTokenIterator, old_value_opt: ?Var) util.Result(Var, []const u8) {
    const value_str = parts.next() orelse return .{ .err = "Premature end of command after operator, expecting value" };
    const first_value = std.fmt.parseInt(i32, value_str, 10) catch return .{ .err = "Invalid integer value (signed 32-bit integer)" };
    switch (operator) {
        .@"=" => {
            return .{ .ok = Var{ .integer = first_value } };
        },
        .@"+=" => {
            if (old_value_opt) |old_value| {
                std.debug.assert(@as(VarTag, old_value) == VarTag.integer);
                return .{ .ok = Var{ .integer = old_value.integer +| first_value } };
            } else {
                return .{ .err = "Cannot add to variable: variable not yet set" };
            }
        },
        .@"-=" => {
            if (old_value_opt) |old_value| {
                std.debug.assert(@as(VarTag, old_value) == VarTag.integer);
                return .{ .ok = Var{ .integer = old_value.integer -| first_value } };
            } else {
                return .{ .err = "Cannot subtract from variable: variable not yet set" };
            }
        },
        .@"@" => {
            if (old_value_opt) |old_value| {
                std.debug.assert(@as(VarTag, old_value) == VarTag.integer);
                var value = first_value;
                while (value != old_value.integer) {
                    const next_value_str = parts.next() orelse
                        // Current value is not in cycle list, return first of cycle list
                        return .{ .ok = Var{ .integer = first_value } };
                    value = std.fmt.parseInt(i32, next_value_str, 10) catch return .{ .err = "Invalid integer value (signed 32-bit integer)" };
                }
                const next_value_str = parts.next() orelse
                    // Current value is last of cycle list, return first of cycle list
                    return .{ .ok = Var{ .integer = first_value } };
                value = std.fmt.parseInt(i32, next_value_str, 10) catch return .{ .err = "Invalid integer value (signed 32-bit integer)" };
                return .{ .ok = Var{ .integer = value } };
            } else {
                return .{ .ok = Var{ .integer = first_value } };
            }
        },
    }
}

fn newVariableValueString(allocator: std.mem.Allocator, operator: Operator, parts: *StringTokenIterator, old_value_opt: ?Var) !util.Result(Var, []const u8) {
    const first_value = parts.next() orelse return .{ .err = "Premature end of command after operator, expecting value" };
    switch (operator) {
        .@"=" => {
            return .{ .ok = Var{ .string = try allocator.dupe(u8, first_value) } };
        },
        .@"@" => {
            if (old_value_opt) |old_value| {
                std.debug.assert(@as(VarTag, old_value) == VarTag.string);
                var value = first_value;
                while (!std.mem.eql(u8, value, old_value.string)) {
                    value = parts.next() orelse
                        // Current value is not in cycle list, return first of cycle list
                        return .{ .ok = Var{ .string = try allocator.dupe(u8, first_value) } };
                }
                value = parts.next() orelse
                    // Current value is last of cycle list, return first of cycle list
                    return .{ .ok = Var{ .string = try allocator.dupe(u8, first_value) } };

                return .{ .ok = Var{ .string = try allocator.dupe(u8, value) } };
            } else {
                return .{ .ok = Var{ .string = try allocator.dupe(u8, first_value) } };
            }
        },
        else => return .{ .err = "Unsupported operator for string variable, supported are = and @" },
    }
}

fn executeTestCommand(cfg: *Config, command: []const u8) !void {
    const result = try cfg.executeCommand(command, .{});
    try std.testing.expectEqual(Result{ .ok = {} }, result);
}

test {
    var cfg = Config.init(std.testing.allocator);
    defer cfg.deinit();
    var variables = &cfg.variables;

    try executeTestCommand(&cfg, "set integer main-count = 3");
    const main_count1 = variables.get("main-count", 0, 0).?;
    try std.testing.expectEqual(@as(i32, 3), main_count1.integer);

    try executeTestCommand(&cfg, "set integer main-count = 1");
    const main_count2 = variables.get("main-count", 0, 0).?;
    try std.testing.expectEqual(@as(i32, 1), main_count2.integer);

    try executeTestCommand(&cfg, "set string override-layout = main-center");
    const override_layout1 = variables.get("override-layout", 0, 0).?;
    try std.testing.expectEqualStrings("main-center", override_layout1.string);

    try executeTestCommand(&cfg, "set string override-layout = main-left");
    const override_layout2 = variables.get("override-layout", 0, 0).?;
    try std.testing.expectEqualStrings("main-left", override_layout2.string);

    try executeTestCommand(&cfg, "set boolean collapse = true");
    const collapse1 = variables.get("collapse", 0, 0).?;
    try std.testing.expectEqual(true, collapse1.boolean);

    try executeTestCommand(&cfg, "set integer column-count @ 1 3 2");
    const column_count1 = variables.get("column-count", 0, 0).?;
    try std.testing.expectEqual(1, column_count1.integer);

    try executeTestCommand(&cfg, "set integer column-count @ 1 3 2");
    const column_count2 = variables.get("column-count", 0, 0).?;
    try std.testing.expectEqual(3, column_count2.integer);

    try executeTestCommand(&cfg, "set integer column-count @ 1 3 2");
    const column_count3 = variables.get("column-count", 0, 0).?;
    try std.testing.expectEqual(2, column_count3.integer);

    try executeTestCommand(&cfg, "set integer column-count @ 1 3 2");
    const column_count4 = variables.get("column-count", 0, 0).?;
    try std.testing.expectEqual(1, column_count4.integer);

    try executeTestCommand(&cfg, "set string layout @ main monocle");
    const layout1 = variables.get("layout", 0, 0).?;
    try std.testing.expectEqualStrings("main", layout1.string);

    try executeTestCommand(&cfg, "set string layout @ main monocle");
    const layout2 = variables.get("layout", 0, 0).?;
    try std.testing.expectEqualStrings("monocle", layout2.string);

    try executeTestCommand(&cfg, "set string layout @ main monocle");
    const layout3 = variables.get("layout", 0, 0).?;
    try std.testing.expectEqualStrings("main", layout3.string);
}
