const std = @import("std");
const Move = @import("../move.zig").Move;
const MoveType = @import("../move.zig").MoveType;
const PieceType = @import("../piece.zig").PieceType;
const Square = @import("../board.zig").Square;
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
    const moves = comptime [_]Move{
        Move.init(Square.sq(.a1), Square.sq(.a2), MoveType.Normal, null),
        Move.init(Square.sq(.b2), Square.sq(.b3), MoveType.DoublePush, null),
        Move.init(Square.sq(.c3), Square.sq(.c4), MoveType.NoCapture, null),
        Move.init(Square.sq(.d4), Square.sq(.e5), MoveType.Capture, null),
        Move.init(Square.sq(.f5), Square.sq(.g6), MoveType.EnPassant, null),
        Move.init(Square.sq(.h7), Square.sq(.h8), MoveType.Normal, PieceType.Queen),
    };

    const expected = comptime [_][]const u8{
        "a1a2",
        "b2b3",
        "c3c4",
        "d4e5",
        "f5g6",
        "h7h8q",
    };

    inline for (moves, expected) |move, ex| {
        const moveStr = try move.toString();
        try std.testing.expectEqualSlices(u8, ex, moveStr);
    }
}
