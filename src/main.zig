// Layout generator for river <https://github.com/ifreund/river>
//
// Copyright 2021 Hugo Machet
// Copyright 2024 Midgard
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const build_options = @import("build_options");

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const os = std.os;

const flags = @import("flags");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const layout = @import("./layout.zig");
const config = @import("./config.zig");
const util = @import("./util.zig");

const log = std.log.scoped(.@"river-ultitile");

const gpa = std.heap.c_allocator;

const usage =
    \\Usage: river-ultitile [options...]
    \\
    \\  -h              Print this help message and exit.
    \\  --version       Print the version number and exit.
    \\
    \\  See river-ultitile(1) man page for more documentation.
    \\
;

const Context = struct {
    layout_manager: ?*river.LayoutManagerV3 = null,
    outputs: std.SinglyLinkedList(Output) = .{},
    initialized: bool = false,
};

var ctx: Context = .{};
var cfg = config.Config.init(gpa);

const Output = struct {
    wl_output: *wl.Output,
    name: u32,

    layout: *river.LayoutV3 = undefined,

    tags: u32,

    fn get_layout(output: *Output) !void {
        // TODO Run once per named layout (and pass layout namespace)
        output.layout = try ctx.layout_manager.?.getLayout(output.wl_output, "river-ultitile");
        output.layout.setListener(*Output, layout_listener, output);
        log.info("Bound river-ultitile to output {}\n", .{output.name});
    }

    fn layout_listener(layout_proto: *river.LayoutV3, event: river.LayoutV3.Event, output: *Output) void {
        switch (event) {
            .namespace_in_use => fatal("namespace 'river-ultitile' already in use.", .{}),

            .user_command => |ev| {
                const command = mem.span(ev.command);
                const result = cfg.executeCommand(command) catch |err| switch (err) {
                    error.OutOfMemory => fatal("out of memory", .{}),
                };
                switch (result) {
                    .ok => {},
                    .err => |err| log.err("error executing command '{s}': {s}", .{ command, err }),
                }
            },
            .user_command_tags => |ev| {
                output.tags = ev.tags;
            },

            .layout_demand => |ev| {
                output.tags = ev.tags;
                handle_layout_demand(layout_proto, output, ev.view_count, ev.usable_width, ev.usable_height, ev.serial) catch |err| {
                    log.err("failed to handle layout demand: {}", .{err});
                    return;
                };
            },
        }
    }
};

fn handle_layout_demand(layout_proto: *river.LayoutV3, output: *Output, view_count: u32, usable_width: u32, usable_height: u32, serial: u32) !void {
    assert(view_count > 0);

    var allocator_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer allocator_instance.deinit();
    const allocator = allocator_instance.allocator();

    const root_tile = cfg.getLayoutSpecification(output.name) orelse cfg.getDefaultLayoutSpecification() orelse return error.NoLayouts;

    var view_dimensions = try layout.layout(allocator, root_tile, view_count, @as(u31, @truncate(usable_width)), @as(u31, @truncate(usable_height)));

    log.info("Proposing {} views:", .{view_dimensions.len});
    for (view_dimensions) |dim| {
        log.info("- {}+{} {}x{}", .{ dim.x, dim.y, dim.width, dim.height });
        layout_proto.pushViewDimensions(
            dim.x,
            dim.y,
            dim.width,
            dim.height,
            serial,
        );
    }

    const name_sentinel = try util.sliceToSentinelPtr(allocator, u8, 0, root_tile.name);
    layout_proto.commit(name_sentinel, serial);
}

pub fn main() !void {
    (try cfg.executeCommand("new layout hstack type=hsplit padding=5 margin=5 max-views=unlimited")).ok;

    (try cfg.executeCommand("new layout vstack type=vsplit padding=5 margin=5 max-views=unlimited")).ok;

    (try cfg.executeCommand("new layout main-left type=hsplit padding=5 margin=5")).ok;
    (try cfg.executeCommand("new tile main-left.left type=vsplit stretch=40 order=2")).ok;
    (try cfg.executeCommand("new tile main-left.main type=vsplit stretch=60 order=1 max-views=1")).ok;

    (try cfg.executeCommand("new layout main-center type=hsplit padding=5 margin=5")).ok;
    (try cfg.executeCommand("new tile main-center.left type=vsplit stretch=25 order=2 suborder=0")).ok;
    (try cfg.executeCommand("new tile main-center.main type=vsplit stretch=50 order=1 max-views=1")).ok;
    (try cfg.executeCommand("new tile main-center.right type=vsplit stretch=25 order=2 suborder=1")).ok;

    (try cfg.executeCommand("new layout monocle type=overlay max-views=unlimited")).ok;

    (try cfg.executeCommand("default layout main-center")).ok;

    // TODO ensure that a default layout has been set after init file has been read

    const res = flags.parser([*:0]const u8, &.{
        .{ .name = "h", .kind = .boolean },
        .{ .name = "-version", .kind = .boolean },
    }).parse(os.argv[1..]) catch {
        try std.io.getStdErr().writeAll(usage);
        os.exit(1);
    };
    if (res.args.len != 0) fatal_usage("Unknown option '{s}'", .{res.args[0]});

    if (res.flags.h) {
        try std.io.getStdOut().writeAll(usage);
        os.exit(0);
    }
    if (res.flags.@"-version") {
        try std.io.getStdOut().writeAll(build_options.version ++ "\n");
        os.exit(0);
    }

    const display = wl.Display.connect(null) catch {
        fatal("unable to connect to wayland compositor", .{});
    };
    defer display.disconnect();

    const registry = try display.getRegistry();
    defer registry.destroy();
    registry.setListener(*Context, registry_listener, &ctx);

    const errno = display.roundtrip();
    if (errno != .SUCCESS) {
        fatal("initial roundtrip failed: E{s}", .{@tagName(errno)});
    }

    if (ctx.layout_manager == null) {
        fatal("Wayland compositor does not support river_layout_v3.\n", .{});
    }

    ctx.initialized = true;

    var it = ctx.outputs.first;
    while (it) |node| : (it = node.next) {
        try node.data.get_layout();
    }

    while (true) {
        const dispatch_errno = display.dispatch();
        if (dispatch_errno != .SUCCESS) {
            fatal("failed to dispatch wayland events, E:{s}", .{@tagName(dispatch_errno)});
        }
    }
}

fn registry_listener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    registry_event(context, registry, event) catch |err| switch (err) {
        error.OutOfMemory => {
            log.err("out of memory", .{});
            return;
        },
        else => return,
    };
}

fn registry_event(context: *Context, registry: *wl.Registry, event: wl.Registry.Event) !void {
    switch (event) {
        .global => |ev| {
            if (mem.orderZ(u8, ev.interface, river.LayoutManagerV3.getInterface().name) == .eq) {
                context.layout_manager = try registry.bind(ev.name, river.LayoutManagerV3, 2);
            } else if (mem.orderZ(u8, ev.interface, wl.Output.getInterface().name) == .eq) {
                const wl_output = try registry.bind(ev.name, wl.Output, 4);
                errdefer wl_output.release();

                const node = try gpa.create(std.SinglyLinkedList(Output).Node);
                errdefer gpa.destroy(node);

                node.data = .{
                    .wl_output = wl_output,
                    .name = ev.name,
                    .tags = 0,
                };

                if (ctx.initialized) try node.data.get_layout();
                context.outputs.prepend(node);
            }
        },
        .global_remove => |ev| {
            var it = context.outputs.first;
            while (it) |node| : (it = node.next) {
                if (node.data.name == ev.name) {
                    node.data.wl_output.release();
                    node.data.layout.destroy();
                    _ = cfg.output__active_layout_specification__map.remove(node.data.name);
                    context.outputs.remove(node);
                    gpa.destroy(node);
                    break;
                }
            }
        },
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    log.err(format, args);
    os.exit(1);
}

fn fatal_usage(comptime format: []const u8, args: anytype) noreturn {
    log.err(format, args);
    std.io.getStdErr().writeAll(usage) catch {};
    os.exit(1);
}
