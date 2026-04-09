const std = @import("std");
const Move = @import("../move.zig").Move;
const Piece = @import("../piece.zig");

test "char to piece" {
    try std.testing.expectEqualDeep(Piece.Piece.fromChar('p'), Piece.Piece.new(.Pawn, .Black));
    try std.testing.expectEqualDeep(Piece.Piece.fromChar('B'), Piece.Piece.new(.Bishop, .White));
    try std.testing.expectEqualDeep(Piece.Piece.fromChar('n'), Piece.Piece.new(.Knight, .Black));
    try std.testing.expectEqualDeep(Piece.Piece.fromChar('R'), Piece.Piece.new(.Rook, .White));
    try std.testing.expectEqualDeep(Piece.Piece.fromChar('q'), Piece.Piece.new(.Queen, .Black));
    try std.testing.expectEqualDeep(Piece.Piece.fromChar('K'), Piece.Piece.new(.King, .White));
}

test "move to string" {
    const expected = comptime [_][]const u8{
        "a1a2",
        "b2b3",
        "c3c4",
        "d4e5",
        "f5g6",
        "h7h8q",
    };

    inline for (expected) |ex| {
        const move = try Move.fromUCIStr(ex);
        const moveStr = try move.toString(std.testing.allocator);
        defer std.testing.allocator.free(moveStr);
        try std.testing.expectEqualSlices(u8, ex, moveStr);
    }
}
