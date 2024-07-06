// river-ultitile <https://sr.ht/~midgard/river-ultitile>
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

const flags = @import("flags");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;
const zriver = wayland.client.zriver;

const layout = @import("layout.zig");
const user_config = @import("user_config.zig");
const config = @import("config.zig");
const util = @import("util.zig");

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

pub const Context = struct {
    layout_manager: ?*river.LayoutManagerV3 = null,
    status_manager: ?*zriver.StatusManagerV1 = null,
    outputs: std.SinglyLinkedList(Output) = .{},
    // XXX Assumes there's only a single seat -- unclear how the river-layout protocol would have to work with multiple seats anyway
    seat: ?Seat = null,
    initialized: bool = false,
};

var ctx: Context = .{};
var cfg = config.Config.init(gpa);

const Output = struct {
    wl_output: *wl.Output,
    name: u32,

    layout: *river.LayoutV3 = undefined,

    tags: u32,

    fn getLayout(output: *Output) !void {
        // TODO Run once per named layout (and pass layout namespace)
        output.layout = try ctx.layout_manager.?.getLayout(output.wl_output, "river-ultitile");
        output.layout.setListener(*Output, layoutListener, output);
        log.info("Bound river-ultitile to output {}\n", .{output.name});
    }

    fn layoutListener(layout_proto: *river.LayoutV3, event: river.LayoutV3.Event, output: *Output) void {
        switch (event) {
            .namespace_in_use => fatal("namespace 'river-ultitile' already in use.", .{}),

            .user_command => |ev| {
                const command = mem.span(ev.command);
                const result = cfg.executeCommand(command, &ctx) catch |err| switch (err) {
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
                handleLayoutDemand(layout_proto, output, ev.view_count, ev.usable_width, ev.usable_height, ev.serial) catch |err| {
                    log.err("failed to handle layout demand: {}", .{err});
                    return;
                };
            },
        }
    }
};

fn findOutput(output: *wl.Output) ?*Output {
    var it = ctx.outputs.first;
    while (it) |node| : (it = node.next) {
        if (node.data.wl_output == output) {
            return &node.data;
        }
    }
    return null;
}

const Seat = struct {
    wl_seat: *wl.Seat,
    name: u32,

    focused_output: ?*Output = null,

    fn getRiverSeatStatus(self: *Seat) !void {
        const status_manager = try ctx.status_manager.?.getRiverSeatStatus(ctx.seat.?.wl_seat);
        status_manager.setListener(*Seat, seatListener, self);
        log.info("Tracking active output from seat {}\n", .{ctx.seat.?.name});
    }

    fn seatListener(layout_proto: *zriver.SeatStatusV1, event: zriver.SeatStatusV1.Event, seat: *Seat) void {
        _ = layout_proto;
        switch (event) {
            .focused_output => |ev| if (ev.output) |output| {
                seat.focused_output = findOutput(output);
                if (seat.focused_output) |focused_output| {
                    log.debug("Now focused: output {}\n", .{focused_output.name});
                } else {
                    log.debug("Now focused: unregistered output (null) :?\n", .{});
                }
            } else {
                log.debug("Focus on output {?} lost\n", .{seat.focused_output});
                seat.focused_output = null;
            },
            else => {},
        }
    }
};

fn handleLayoutDemand(layout_proto: *river.LayoutV3, output: *Output, view_count: u32, usable_width: u32, usable_height: u32, serial: u32) !void {
    assert(view_count > 0);

    var allocator_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer allocator_instance.deinit();
    const allocator = allocator_instance.allocator();

    const root_tile = try user_config.layoutSpecification(allocator, &cfg.variables, view_count, usable_width, usable_height, output.name, output.tags);

    const view_dimensions = try layout.layout(allocator, &root_tile, view_count, @as(u31, @truncate(usable_width)), @as(u31, @truncate(usable_height)));

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
    const res = flags.parser([*:0]const u8, &.{
        .{ .name = "h", .kind = .boolean },
        .{ .name = "-version", .kind = .boolean },
    }).parse(std.os.argv[1..]) catch {
        try std.io.getStdErr().writeAll(usage);
        std.posix.exit(1);
    };
    if (res.args.len != 0) fatalUsage("Unknown option '{s}'", .{res.args[0]});

    if (res.flags.h) {
        try std.io.getStdOut().writeAll(usage);
        std.posix.exit(0);
    }
    if (res.flags.@"-version") {
        try std.io.getStdOut().writeAll(build_options.version ++ "\n");
        std.posix.exit(0);
    }

    try user_config.setDefaultVariables(&cfg.variables);

    const display = wl.Display.connect(null) catch {
        fatal("unable to connect to wayland compositor", .{});
    };
    defer display.disconnect();

    const registry = try display.getRegistry();
    defer registry.destroy();
    registry.setListener(*Context, registryListener, &ctx);

    const errno = display.roundtrip();
    if (errno != .SUCCESS) {
        fatal("initial roundtrip failed: E{s}", .{@tagName(errno)});
    }

    if (ctx.layout_manager == null) {
        fatal("Wayland compositor does not support river_layout_v3.\n", .{});
    }

    if (ctx.status_manager == null) {
        fatal("Wayland compositor does not support zriver_status_unstable_v1.\n", .{});
    }

    ctx.initialized = true;

    var it = ctx.outputs.first;
    while (it) |node| : (it = node.next) {
        try node.data.getLayout();
    }

    if (ctx.initialized) try ctx.seat.?.getRiverSeatStatus();

    while (true) {
        const dispatch_errno = display.dispatch();
        if (dispatch_errno != .SUCCESS) {
            fatal("failed to dispatch wayland events, E:{s}", .{@tagName(dispatch_errno)});
        }
    }
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    registryEvent(context, registry, event) catch |err| switch (err) {
        error.OutOfMemory => {
            log.err("out of memory", .{});
            return;
        },
        else => return,
    };
}

fn registryEvent(context: *Context, registry: *wl.Registry, event: wl.Registry.Event) !void {
    switch (event) {
        .global => |ev| {
            if (mem.orderZ(u8, ev.interface, river.LayoutManagerV3.getInterface().name) == .eq) {
                context.layout_manager = try registry.bind(ev.name, river.LayoutManagerV3, 2);
            } else if (mem.orderZ(u8, ev.interface, zriver.StatusManagerV1.getInterface().name) == .eq) {
                context.status_manager = try registry.bind(ev.name, zriver.StatusManagerV1, 4);
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

                if (ctx.initialized) try node.data.getLayout();
                context.outputs.prepend(node);
            } else if (mem.orderZ(u8, ev.interface, wl.Seat.getInterface().name) == .eq) {
                const wl_seat = try registry.bind(ev.name, wl.Seat, 4);
                errdefer wl_seat.release();

                ctx.seat = .{
                    .wl_seat = wl_seat,
                    .name = ev.name,
                };

                if (ctx.initialized) try ctx.seat.?.getRiverSeatStatus();
            }
        },
        .global_remove => |ev| {
            var it = context.outputs.first;
            while (it) |node| : (it = node.next) {
                if (node.data.name == ev.name) {
                    node.data.wl_output.release();
                    node.data.layout.destroy();
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
    std.posix.exit(1);
}

fn fatalUsage(comptime format: []const u8, args: anytype) noreturn {
    log.err(format, args);
    std.io.getStdErr().writeAll(usage) catch {};
    std.posix.exit(1);
}
