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
    var slice = try tokenIteratorAsSlice(u8, .scalar, std.testing.allocator, &token_iterator);
    try std.testing.expectEqualDeep(.{ "a", "bb", "c" }, slice);
    std.testing.allocator.free(slice);
}
