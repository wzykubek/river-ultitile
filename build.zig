const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const mem = std.mem;

const Scanner = @import("wayland").Scanner;

// Read build.zig.zon
// Awaiting https://github.com/ziglang/zig/issues/22775 to just @import("build.zig.zon")
const build_zig_zon = @embedFile("build.zig.zon");
const PackageMetadata = struct {
    version: std.SemanticVersion,
    version_string: []const u8,
    zig_version: std.SemanticVersion,
};
fn packageMetadata(allocator: std.mem.Allocator) !PackageMetadata {
    var parse_status: std.zon.parse.Status = .{};
    defer parse_status.deinit(allocator);
    const build_zon = std.zon.parse.fromSlice(struct { version: []const u8, zig_version: []const u8 }, allocator, build_zig_zon, &parse_status, .{ .ignore_unknown_fields = true }) catch |e| {
        std.log.err("{}", .{parse_status});
        return e;
    };
    return .{ .version = try std.SemanticVersion.parse(build_zon.version), .version_string = build_zon.version, .zig_version = try std.SemanticVersion.parse(build_zon.zig_version) };
}

fn compatibleZig(actual: std.SemanticVersion, required: std.SemanticVersion) bool {
    return actual.order(required) != .lt and actual.major == required.major and (actual.minor == required.minor or required.major > 0);
}

pub fn build(b: *std.Build) !void {
    const package_metadata = try packageMetadata(b.allocator);
    // Check Zig version
    if (!compatibleZig(builtin.zig_version, package_metadata.zig_version)) {
        std.log.err("requires a Zig version compatible with {}, but found {}", .{ package_metadata.zig_version, builtin.zig_version });
        std.process.exit(2);
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pie = b.option(bool, "pie", "Build a Position Independent Executable") orelse false;

    const full_version = blk: {
        var ret: u8 = undefined;

        if (mem.endsWith(u8, package_metadata.version_string, "dev")) {
            const git_describe_long = b.runAllowFail(
                &[_][]const u8{ "git", "-C", b.build_root.path orelse ".", "describe", "--long" },
                &ret,
                .Inherit,
            ) catch break :blk package_metadata.version_string;

            var it = mem.splitScalar(u8, mem.trim(u8, git_describe_long, &std.ascii.whitespace), '-');
            _ = it.next().?; // previous tag
            const commit_count = it.next().?;
            const commit_hash = it.next().?;
            assert(it.next() == null);
            assert(commit_hash[0] == 'g');

            // Follow semantic versioning, e.g. 0.2.0-dev.42+d1cf95b
            break :blk try std.fmt.allocPrintZ(b.allocator, "{}.{s}+{s}", .{
                package_metadata.version,
                commit_count,
                commit_hash[1..],
            });
        } else {
            const git_describe = b.runAllowFail(
                &[_][]const u8{ "git", "-C", b.build_root.path orelse ".", "describe" },
                &ret,
                .Inherit,
            ) catch break :blk package_metadata.version_string;
            if (git_describe.len == package_metadata.version_string.len + 2 and git_describe[0] == 'v' and git_describe[git_describe.len - 1] == '\n' and mem.eql(u8, git_describe[1 .. git_describe.len - 1], package_metadata.version_string)) {
                break :blk package_metadata.version_string;
            } else {
                std.log.err("version in build.zig.zon ({}) does not match git tag ({s}). After a release, the version in build.zig.zon should be made to end with -dev", .{ package_metadata.version, git_describe[1 .. git_describe.len - 1] });
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

    scanner.addCustomProtocol(b.path("protocol/river-layout-v3.xml"));

    scanner.generate("wl_output", 4);
    scanner.generate("river_layout_manager_v3", 2);

    const wayland = b.createModule(.{ .root_source_file = scanner.result });
    const flags = b.createModule(.{ .root_source_file = b.path("common/flags.zig") });

    const exe = b.addExecutable(.{
        .name = "river-ultitile",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addOptions("build_options", options);

    exe.linkLibC();

    exe.root_module.addImport("wayland", wayland);
    exe.linkSystemLibrary("wayland-client");

    exe.root_module.addImport("flags", flags);

    exe.pie = pie;

    b.installArtifact(exe);

    const command = try std.fmt.allocPrint(b.allocator, "sed 's|\\[CONTRIBUTING.md\\]|https://git.sr.ht/~midgard/river-ultitile/tree/main/item/CONTRIBUTING.md|g' README.md | " ++
        "pandoc -fmarkdown -Vtitle:RIVER-ULTITILE -Vsection:1 -Vdate:'{s}' -Vfooter:'river-ultitile {s}' -tman --template=default.man -odoc/river-ultitile.1", .{ date, full_version });

    _ = b.run(&.{ "sh", "-c", command });
    b.installFile("doc/river-ultitile.1", "share/man/man1/river-ultitile.1");
}
