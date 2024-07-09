const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;

const Scanner = @import("zig-wayland").Scanner;

/// While a river-ultitile release is in development, this string should contain
/// the version in development with the "-dev" suffix.  When a release is
/// tagged, the "-dev" suffix should be removed for the commit that gets tagged.
/// Directly after the tagged commit, the version should be bumped and the "-dev"
/// suffix added.
const version = "1.0.0-dev";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pie = b.option(bool, "pie", "Build a Position Independent Executable") orelse false;

    const full_version = blk: {
        var ret: u8 = undefined;

        if (mem.endsWith(u8, version, "-dev")) {
            const git_describe_long = b.runAllowFail(
                &[_][]const u8{ "git", "-C", b.build_root.path orelse ".", "describe", "--long" },
                &ret,
                .Inherit,
            ) catch break :blk version;

            var it = mem.split(u8, mem.trim(u8, git_describe_long, &std.ascii.whitespace), "-");
            _ = it.next().?; // previous tag
            const commit_count = it.next().?;
            const commit_hash = it.next().?;
            assert(it.next() == null);
            assert(commit_hash[0] == 'g');

            // Follow semantic versioning, e.g. 0.2.0-dev.42+d1cf95b
            break :blk try std.fmt.allocPrintZ(b.allocator, version ++ ".{s}+{s}", .{
                commit_count,
                commit_hash[1..],
            });
        } else {
            const git_describe = b.runAllowFail(
                &[_][]const u8{ "git", "-C", b.build_root.path orelse ".", "describe" },
                &ret,
                .Inherit,
            ) catch break :blk version;
            if (mem.eql(u8, git_describe, version)) {
                break :blk version;
            } else {
                std.debug.print("version does not match git tag\n", .{});
                std.process.exit(1);
            }
        }
    };
    const date = blk: {
        var ret: u8 = undefined;

        break :blk b.runAllowFail(
            &.{ "date", "--utc", "+%Y-%m-%d" },
            &ret,
            .Inherit,
        ) catch "unknown";
    };

    const options = b.addOptions();
    options.addOption([]const u8, "version", full_version);

    const scanner = Scanner.create(b, .{});

    scanner.addCustomProtocol("protocol/river-layout-v3.xml");
    scanner.addCustomProtocol("protocol/river-status-unstable-v1.xml");

    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 9);
    scanner.generate("river_layout_manager_v3", 2);
    scanner.generate("zriver_status_manager_v1", 4);

    const wayland = b.createModule(.{ .root_source_file = scanner.result });
    const flags = b.createModule(.{ .root_source_file = .{ .path = "common/flags.zig" } });

    const exe = b.addExecutable(.{
        .name = "river-ultitile",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addOptions("build_options", options);

    exe.linkLibC();

    exe.root_module.addImport("wayland", wayland);
    exe.linkSystemLibrary("wayland-client");

    exe.root_module.addImport("flags", flags);

    scanner.addCSource(exe);

    exe.pie = pie;

    b.installArtifact(exe);

    const command = try std.fmt.allocPrint(b.allocator, "sed 's|\\[CONTRIBUTING.md\\]|https://git.sr.ht/~midgard/river-ultitile/tree/main/item/CONTRIBUTING.md|g' README.md | " ++
        "pandoc -fmarkdown -Vtitle:RIVER-ULTITILE -Vsection:1 -Vdate:'{s}' -Vfooter:'river-ultitile {s}' -tman --template=default.man -odoc/river-ultitile.1", .{ date, full_version });

    _ = b.run(&.{ "sh", "-c", command });
    b.installFile("doc/river-ultitile.1", "share/man/man1/river-ultitile.1");
}
