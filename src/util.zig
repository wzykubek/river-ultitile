// river-ultitile <https://sr.ht/~midgard/river-ultitile>
// See main.zig and COPYING for copyright info

const std = @import("std");

pub const ResultTag = enum { ok, err };
pub fn Result(comptime T: type, comptime ErrorT: type) type {
    return union(ResultTag) {
        ok: T,
        err: ErrorT,
    };
}

pub fn tokenIteratorAsSlice(comptime T: type, comptime delim: std.mem.DelimiterType, allocator: std.mem.Allocator, iterator: *std.mem.TokenIterator(T, delim)) ![]const []const T {
    var list = std.ArrayList([]const T).init(allocator);
    while (iterator.next()) |item| {
        try list.append(item);
    }
    return list.toOwnedSlice();
}

test {
    var token_iterator = std.mem.tokenizeScalar(u8, "a.bb.c", '.');
    const slice = try tokenIteratorAsSlice(u8, .scalar, std.testing.allocator, &token_iterator);
    try std.testing.expectEqualDeep(&[_][]const u8{ "a", "bb", "c" }, slice);
    std.testing.allocator.free(slice);
}

/// Caller owns returned memory
pub fn sliceToSentinelPtr(allocator: std.mem.Allocator, comptime T: type, comptime sentinel: T, slice: []const T) ![:sentinel]T {
    var result: [:sentinel]T = try allocator.allocSentinel(T, slice.len + 1, sentinel);
    @memcpy(result[0..slice.len], slice);
    return result;
}
